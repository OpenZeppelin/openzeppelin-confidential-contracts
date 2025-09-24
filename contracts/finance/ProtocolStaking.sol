// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

interface IERC20Mintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract ProtocolStaking is AccessControlDefaultAdminRulesUpgradeable, ERC20VotesUpgradeable, UUPSUpgradeable {
    using Checkpoints for Checkpoints.Trace208;
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 private constant OPERATOR_ROLE = keccak256(bytes("operator-role"));
    // Stake - general
    address private _stakingToken;
    uint256 private _totalStakedWeight;
    // Stake - release
    uint256 private _unstakeCooldownPeriod;
    mapping(address => Checkpoints.Trace208) private _unstakeRequests;
    mapping(address => uint256) private _released;
    // Reward - issuance curve
    uint256 private _lastUpdateTimestamp;
    uint256 private _lastUpdateReward;
    uint256 private _rewardRate;
    // Reward - recipient
    mapping(address => address) private _rewardsRecipient;
    // Reward - payment tracking
    mapping(address => int256) private _paid;
    int256 private _totalPaid;

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
    }

    function stake(uint256 amount) public virtual {
        _stake(amount);
    }

    function unstake(uint256 amount) public virtual {
        _unstake(amount);
    }

    function release() public virtual {
        uint256 totalAmountCooledDown = _unstakeRequests[msg.sender].upperLookup(Time.timestamp());
        uint256 amountToRelease = totalAmountCooledDown - _released[msg.sender];
        _released[msg.sender] = totalAmountCooledDown;
        if (amountToRelease > 0) {
            IERC20(stakingToken()).safeTransfer(msg.sender, amountToRelease);
        }
    }

    function earned(address account) public view virtual returns (uint256) {
        if (isOperator(account)) {
            uint256 stakedWeight = weight(balanceOf(account));
            // if personalShares == 0, there is a risk of totalShares == 0. To avoid div by 0 just return 0
            uint256 allocation = stakedWeight > 0 ? _allocation(stakedWeight, _totalStakedWeight) : 0;
            return SafeCast.toUint256(SafeCast.toInt256(allocation) - _paid[account]);
        } else {
            return 0;
        }
    }

    /// @dev Claim staking rewards for `account`.
    function claimRewards(address account) public virtual {
        uint256 rewards = earned(account);
        if (rewards > 0) {
            _paid[account] += SafeCast.toInt256(rewards);
            IERC20Mintable(stakingToken()).mint(rewardsRecipient(account), rewards);
        }
    }

    function addOperator(address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!isOperator(account), OperatorAlreadyExists(account));
        _grantRole(OPERATOR_ROLE, account);
        _updateRewards(account, 0, weight(balanceOf(account)));
        emit OperatorAdded(account);
    }

    function removeOperator(address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isOperator(account), OperatorDoesNotExist(account));
        _revokeRole(OPERATOR_ROLE, account);
        _updateRewards(account, weight(balanceOf(account)), 0);
        emit OperatorRemoved(account);
    }

    function setRewardRate(uint256 rewardRate) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _lastUpdateReward = _historicalReward();
        _lastUpdateTimestamp = Time.timestamp();
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
        return _unstakeRequests[account].latest() - _released[account];
    }

    /// @notice Returns the recipient for rewards earned by `account`.
    function rewardsRecipient(address account) public view virtual returns (address) {
        address storedRewardsRecipient = _rewardsRecipient[account];
        return storedRewardsRecipient == address(0) ? account : storedRewardsRecipient;
    }

    function _stake(uint256 amount) internal virtual {
        _mint(msg.sender, amount);
        IERC20(stakingToken()).safeTransferFrom(msg.sender, address(this), amount);

        emit TokensStaked(msg.sender, amount);
    }

    function _unstake(uint256 amount) internal virtual {
        require(amount != 0, InvalidAmount());
        _burn(msg.sender, amount);

        if (_unstakeCooldownPeriod == 0) {
            IERC20(stakingToken()).safeTransfer(msg.sender, amount);
        } else {
            (, uint256 lastReleaseTime, uint256 totalRequestedToWithdraw) = _unstakeRequests[msg.sender]
                .latestCheckpoint();
            uint256 releaseTime = Time.timestamp() + _unstakeCooldownPeriod;
            _unstakeRequests[msg.sender].push(
                uint48(Math.max(releaseTime, lastReleaseTime)),
                uint208(totalRequestedToWithdraw + amount)
            );
        }

        emit TokensUnstaked(msg.sender, amount);
    }

    function _historicalReward() public view virtual returns (uint256) {
        return _lastUpdateReward + (Time.timestamp() - _lastUpdateTimestamp) * _rewardRate;
    }

    function _allocation(uint256 share, uint256 total) private view returns (uint256) {
        return SafeCast.toUint256(SafeCast.toInt256(_historicalReward()) + _totalPaid).mulDiv(share, total);
    }

    function _updateRewards(address user, uint256 weightBefore, uint256 weightAfter) internal {
        uint256 oldTotalWeight = _totalStakedWeight;
        _totalStakedWeight = oldTotalWeight - weightBefore + weightAfter;

        if (weightBefore != weightAfter && oldTotalWeight > 0) {
            if (weightBefore > weightAfter) {
                int256 virtualAmount = SafeCast.toInt256(_allocation(weightBefore - weightAfter, oldTotalWeight));
                _paid[user] -= virtualAmount;
                _totalPaid -= virtualAmount;
            } else {
                int256 virtualAmount = SafeCast.toInt256(_allocation(weightAfter - weightBefore, oldTotalWeight));
                _paid[user] += virtualAmount;
                _totalPaid += virtualAmount;
            }
        }
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        // MARK: Disable Transfers
        require(from == address(0) || to == address(0), TransferDisabled());
        if (isOperator(from)) {
            uint256 balanceBefore = balanceOf(from);
            uint256 balanceAfter = balanceBefore - value;
            _updateRewards(from, weight(balanceBefore), weight(balanceAfter));
        }
        if (isOperator(to)) {
            uint256 balanceBefore = balanceOf(to);
            uint256 balanceAfter = balanceBefore + value;
            _updateRewards(to, weight(balanceBefore), weight(balanceAfter));
        }
        super._update(from, to, value);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
