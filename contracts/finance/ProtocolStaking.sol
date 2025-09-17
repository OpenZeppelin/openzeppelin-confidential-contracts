// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Votes, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

interface IERC20Mintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract ProtocolStaking is Ownable, ERC20Votes {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Checkpoints for Checkpoints.Trace208;
    using SafeERC20 for IERC20;

    struct UserStakingInfo {
        uint256 rewardsPerUnitPaid;
        uint256 rewards;
    }

    EnumerableSet.AddressSet private _operators;
    address private _stakingToken;
    uint256 private _totalStakedLog;
    uint256 private _lastUpdateTimestamp;
    uint256 private _rewardsPerUnit = 1;
    uint256 private _rewardRate;
    uint256 private _unstakeCooldownPeriod;
    mapping(address => UserStakingInfo) private _userStakingInfo;
    mapping(address => Checkpoints.Trace208) private _unstakeRequests;
    mapping(address => uint256) private _totalReleased;

    event OperatorAdded(address operator);
    event OperatorRemoved(address operator);
    event TokensStaked(address operator, uint256 amount);
    event TokensUnstaked(address operator, uint256 amount);

    error InvalidAmount();
    error OperatorAlreadyExists(address operator);
    error OperatorDoesNotExist(address operator);

    constructor(
        string memory name,
        string memory symbol,
        string memory version,
        address stakingToken_,
        address governor
    ) Ownable(governor) ERC20(name, symbol) EIP712(name, version) {
        _stakingToken = stakingToken_;
    }

    function stake(uint256 amount) public virtual {
        _stake(amount);
    }

    function unstake(uint256 amount) public virtual {
        _unstake(amount);
    }

    function release() public virtual {
        uint256 totalAmountCooledDown = _unstakeRequests[msg.sender].upperLookup(uint48(block.timestamp));
        uint256 amountToRelease = totalAmountCooledDown - _totalReleased[msg.sender];
        _totalReleased[msg.sender] = totalAmountCooledDown;
        if (amountToRelease > 0) {
            IERC20(_stakingToken).safeTransfer(msg.sender, amountToRelease);
        }
    }

    function earned(address account) public view virtual returns (uint256) {
        UserStakingInfo memory userInfo = _userStakingInfo[account];
        if (userInfo.rewardsPerUnitPaid == 0) {
            return userInfo.rewards;
        }
        return (log(balanceOf(account)) * (_rewardsPerUnit - userInfo.rewardsPerUnitPaid)) / 1e18 + userInfo.rewards;
    }

    /// @dev Claim staking rewards for `account`.
    function claimRewards(address account) public virtual {
        _updateRewards();
        _updateRewards(account);

        uint256 rewards = _userStakingInfo[account].rewards;
        if (rewards > 0) {
            _userStakingInfo[account].rewards = 0;
            IERC20Mintable(_stakingToken).mint(account, rewards);
        }
    }

    function operators() public view virtual returns (address[] memory) {
        return _operators.values();
    }

    function isOperator(address account) public view virtual returns (bool) {
        return _operators.contains(account);
    }

    function addOperator(address account) public virtual onlyOwner {
        require(_operators.add(account), OperatorAlreadyExists(account));

        _updateRewards();
        _userStakingInfo[account].rewardsPerUnitPaid = _rewardsPerUnit;

        _totalStakedLog += log(balanceOf(account));

        emit OperatorAdded(account);
    }

    function removeOperator(address account) public virtual onlyOwner {
        require(_operators.remove(account), OperatorDoesNotExist(account));

        _updateRewards();
        _updateRewards(account);
        _userStakingInfo[account].rewardsPerUnitPaid = 0;

        _totalStakedLog -= log(balanceOf(account));

        emit OperatorRemoved(account);
    }

    function setRewardRate(uint256 rewardRate) public virtual onlyOwner {
        _updateRewards();
        _rewardRate = rewardRate;
    }

    function setUnstakeCooldownPeriod(uint256 unstakeCooldownPeriod) public virtual onlyOwner {
        _unstakeCooldownPeriod = unstakeCooldownPeriod;
    }

    /// @dev Calculate the logarithm base 2 of the amount `amount`.
    function log(uint256 amount) public view virtual returns (uint256) {
        return Math.log2(amount);
    }

    /// @dev Returns the staking token which is used for staking and rewards.
    function stakingToken() public view virtual returns (address) {
        return _stakingToken;
    }

    function totalStakedLog() public view virtual returns (uint256) {
        return _totalStakedLog;
    }

    function _stake(uint256 amount) internal virtual {
        _updateRewards();
        _updateRewards(msg.sender);

        if (isOperator(msg.sender)) {
            uint256 previousStakedAmount = balanceOf(msg.sender);
            uint256 newStakedAmount = previousStakedAmount + amount;

            _totalStakedLog = _totalStakedLog + log(newStakedAmount) - log(previousStakedAmount);
        }

        _mint(msg.sender, amount);
        IERC20(_stakingToken).safeTransferFrom(msg.sender, address(this), amount);

        emit TokensStaked(msg.sender, amount);
    }

    function _unstake(uint256 amount) internal virtual {
        _updateRewards();
        _updateRewards(msg.sender);

        require(amount != 0, InvalidAmount());

        if (isOperator(msg.sender)) {
            uint256 previousStakedAmount = balanceOf(msg.sender);
            uint256 newStakedAmount = previousStakedAmount - amount;

            _totalStakedLog = _totalStakedLog + log(newStakedAmount) - log(previousStakedAmount);
        }

        _burn(msg.sender, amount);

        if (_unstakeCooldownPeriod == 0) {
            IERC20(_stakingToken).safeTransfer(msg.sender, amount);
        } else {
            uint256 releaseTime = block.timestamp + _unstakeCooldownPeriod;
            _unstakeRequests[msg.sender].push(
                uint48(releaseTime),
                uint208(_unstakeRequests[msg.sender].latest() + amount)
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

        if (_totalStakedLog == 0) {
            return;
        }

        uint256 rewardsPerUnitDiff = (secondsElapsed * _rewardRate * 1e18) / _totalStakedLog;
        _rewardsPerUnit += rewardsPerUnitDiff;
        _lastUpdateTimestamp = block.timestamp;
    }

    function _encodeReleaseData(uint48 releaseTime, uint256 amount) private pure returns (bytes32) {
        return bytes32((uint256(releaseTime) << 208) | amount);
    }

    function _decodeReleaseData(bytes32 data) private pure returns (uint48 releaseTime, uint256 amount) {
        amount = uint208(uint256(data));
        releaseTime = uint48(uint256(data) >> 208);
    }

    // MARK: Disable Transfers
    function transfer(address, uint256) public virtual override returns (bool) {
        revert();
    }

    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert();
    }
}
