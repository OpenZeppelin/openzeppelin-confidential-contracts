// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

interface IERC20Mintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract ProtocolStaking is AccessControlDefaultAdminRulesUpgradeable, ERC20VotesUpgradeable, UUPSUpgradeable {
    using Checkpoints for Checkpoints.Trace208;
    using SafeERC20 for IERC20;

    struct UserStakingInfo {
        uint256 rewardsPerUnitPaid;
        uint256 rewards;
    }

    bytes32 private constant OPERATOR_ROLE = keccak256(bytes("operator-role"));
    address private _stakingToken;
    uint256 private _totalStakedWeight;
    uint256 private _lastUpdateTimestamp;
    uint256 private _rewardsPerUnit;
    uint256 private _rewardRate;
    uint256 private _unstakeCooldownPeriod;
    mapping(address => UserStakingInfo) private _userStakingInfo;
    mapping(address => Checkpoints.Trace208) private _unstakeRequests;
    mapping(address => uint256) private _totalReleased;
    mapping(address => address) private _rewardsRecipient;

    event OperatorAdded(address operator);
    event OperatorRemoved(address operator);
    event TokensStaked(address operator, uint256 amount);
    event TokensUnstaked(address operator, uint256 amount);
    event RewardRateSet(uint256 rewardRate);
    event UnstakeCooldownPeriodSet(uint256 unstakeCooldownPeriod);
    event RewardsRecipientSet(address indexed account, address indexed recipient);

    error InvalidAmount();
    error OperatorAlreadyExists(address operator);
    error OperatorDoesNotExist(address operator);
    error TransferDisabled();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        string memory version,
        address stakingToken_,
        address governor
    ) public virtual initializer {
        __AccessControlDefaultAdminRules_init(0, governor);
        __ERC20_init(name, symbol);
        __EIP712_init(name, version);
        _stakingToken = stakingToken_;
        _rewardsPerUnit = 1; // initialize rewards per unit
    }

    function stake(uint256 amount) public virtual {
        _stake(amount);
    }

    function unstake(uint256 amount) public virtual {
        _unstake(amount);
    }

    function release() public virtual {
        uint256 totalAmountCooledDown = _unstakeRequests[msg.sender].upperLookup(Time.timestamp());
        uint256 amountToRelease = totalAmountCooledDown - _totalReleased[msg.sender];
        _totalReleased[msg.sender] = totalAmountCooledDown;
        if (amountToRelease > 0) {
            IERC20(stakingToken()).safeTransfer(msg.sender, amountToRelease);
        }
    }

    function earned(address account) public view virtual returns (uint256) {
        UserStakingInfo memory userInfo = _userStakingInfo[account];
        if (userInfo.rewardsPerUnitPaid == 0) {
            return userInfo.rewards;
        }
        return (weight(balanceOf(account)) * (_rewardsPerUnit - userInfo.rewardsPerUnitPaid)) / 1e18 + userInfo.rewards;
    }

    /// @dev Claim staking rewards for `account`.
    function claimRewards(address account) public virtual {
        _updateRewards();
        _updateRewards(account);

        uint256 rewards = _userStakingInfo[account].rewards;
        if (rewards > 0) {
            _userStakingInfo[account].rewards = 0;
            IERC20Mintable(stakingToken()).mint(rewardsRecipient(account), rewards);
        }
    }

    function addOperator(address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!isOperator(account), OperatorAlreadyExists(account));
        _grantRole(OPERATOR_ROLE, account);

        _updateRewards();
        _userStakingInfo[account].rewardsPerUnitPaid = _rewardsPerUnit;

        _totalStakedWeight += weight(balanceOf(account));

        emit OperatorAdded(account);
    }

    function removeOperator(address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isOperator(account), OperatorDoesNotExist(account));
        _revokeRole(OPERATOR_ROLE, account);

        _updateRewards();
        _updateRewards(account);
        _userStakingInfo[account].rewardsPerUnitPaid = 0;

        _totalStakedWeight -= weight(balanceOf(account));

        emit OperatorRemoved(account);
    }

    function setRewardRate(uint256 rewardRate) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateRewards();
        _rewardRate = rewardRate;

        emit RewardRateSet(rewardRate);
    }

    function setUnstakeCooldownPeriod(uint256 unstakeCooldownPeriod) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _unstakeCooldownPeriod = unstakeCooldownPeriod;

        emit UnstakeCooldownPeriodSet(unstakeCooldownPeriod);
    }

    function setRewardsRecipient(address recipient) public virtual {
        _rewardsRecipient[msg.sender] = recipient;

        emit RewardsRecipientSet(msg.sender, recipient);
    }

    /// @dev Gets the staking weight for a given raw amount.
    function weight(uint256 amount) public view virtual returns (uint256) {
        return Math.log2(amount);
    }

    /// @dev Returns the staking token which is used for staking and rewards.
    function stakingToken() public view virtual returns (address) {
        return _stakingToken;
    }

    function totalStakedWeight() public view virtual returns (uint256) {
        return _totalStakedWeight;
    }

    function isOperator(address account) public view virtual returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /// @notice Returns the amount of tokens cooling down for the given account `account`.
    function tokensInCooldown(address account) public view virtual returns (uint256) {
        return _unstakeRequests[account].latest() - _totalReleased[account];
    }

    /// @notice Returns the recipient for rewards earned by `account`.
    function rewardsRecipient(address account) public view virtual returns (address) {
        address storedRewardsRecipient = _rewardsRecipient[account];
        return storedRewardsRecipient == address(0) ? account : storedRewardsRecipient;
    }

    function _stake(uint256 amount) internal virtual {
        _updateRewards();
        _updateRewards(msg.sender);

        if (isOperator(msg.sender)) {
            uint256 previousStakedAmount = balanceOf(msg.sender);
            uint256 newStakedAmount = previousStakedAmount + amount;

            _totalStakedWeight = _totalStakedWeight + weight(newStakedAmount) - weight(previousStakedAmount);
        }

        _mint(msg.sender, amount);
        IERC20(stakingToken()).safeTransferFrom(msg.sender, address(this), amount);

        emit TokensStaked(msg.sender, amount);
    }

    function _unstake(uint256 amount) internal virtual {
        _updateRewards();
        _updateRewards(msg.sender);

        require(amount != 0, InvalidAmount());

        if (isOperator(msg.sender)) {
            uint256 previousStakedAmount = balanceOf(msg.sender);
            uint256 newStakedAmount = previousStakedAmount - amount;

            _totalStakedWeight = _totalStakedWeight + weight(newStakedAmount) - weight(previousStakedAmount);
        }

        _burn(msg.sender, amount);

        if (_unstakeCooldownPeriod == 0) {
            IERC20(stakingToken()).safeTransfer(msg.sender, amount);
        } else {
            (, uint256 lastReleaseTime, uint256 totalRequestedToWithdraw) = _unstakeRequests[msg.sender]
                .latestCheckpoint();
            uint256 releaseTime = block.timestamp + _unstakeCooldownPeriod;
            _unstakeRequests[msg.sender].push(
                uint48(Math.max(releaseTime, lastReleaseTime)),
                uint208(totalRequestedToWithdraw + amount)
            );
        }

        emit TokensUnstaked(msg.sender, amount);
    }

    function _updateRewards(address account) internal virtual {
        if (_userStakingInfo[account].rewardsPerUnitPaid == 0) return;
        _userStakingInfo[account] = UserStakingInfo({rewards: earned(account), rewardsPerUnitPaid: _rewardsPerUnit});
    }

    function _updateRewards() internal virtual {
        if (block.timestamp == _lastUpdateTimestamp) {
            return;
        }

        uint256 secondsElapsed = block.timestamp - _lastUpdateTimestamp;
        _lastUpdateTimestamp = block.timestamp;

        if (_totalStakedWeight == 0) {
            return;
        }

        uint256 rewardsPerUnitDiff = (secondsElapsed * _rewardRate * 1e18) / _totalStakedWeight;
        _rewardsPerUnit += rewardsPerUnitDiff;
        _lastUpdateTimestamp = block.timestamp;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // MARK: Disable Transfers
    function transfer(address, uint256) public virtual override returns (bool) {
        revert TransferDisabled();
    }

    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert TransferDisabled();
    }
}
