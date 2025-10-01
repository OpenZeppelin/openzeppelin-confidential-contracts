// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IOperatorStaking {
    function asset() external view returns (address);
}

/**
 * @dev A contract handling reward logic to stakers having deposited tokens on an {OperatorStaking} contract.
 */
contract OperatorStakingRewarder is Ownable {
    address private immutable _operatorStaking;
    uint256 private _stakersRewardRatio = 50;
    uint256 private _totalReleased;
    mapping(address => uint256) private _released;

    error SenderNotOperatorStaking(address account);

    event HoldersRewardRatioSet(uint256 stakersRewardRatio);
    event RewardClaimed(address account, uint256 amount);

    modifier onlyOperatorStaking() {
        require(msg.sender == _operatorStaking, SenderNotOperatorStaking(msg.sender));
        _;
    }

    constructor(address owner, address operatorStaking) Ownable(owner) {
        _operatorStaking = operatorStaking;
    }

    /// @dev Gets staking token.
    function stakingToken() public view virtual returns (address) {
        return IOperatorStaking(_operatorStaking).asset();
    }

    /// @dev Gets reward ratio for all stakers.
    function stakersRewardRatio() public view virtual returns (uint256) {
        return _stakersRewardRatio;
    }

    /// @dev Gets reward ratio for operator.
    function operatorRewardRatio() public view virtual returns (uint256) {
        return 100 - _stakersRewardRatio;
    }

    /// @dev Sets reward ratio for all stakers.
    function setHoldersRewardRatio(uint256 stakersRewardRatio_) public virtual onlyOwner {
        _stakersRewardRatio = stakersRewardRatio_;
        emit HoldersRewardRatioSet(stakersRewardRatio_);
    }

    /// @dev
    function totalReleased() public view virtual returns (uint256) {
        return _totalReleased;
    }

    /// @dev
    function released(address account) public view virtual returns (uint256) {
        return _released[account];
    }

    /// @dev Withdraw rewards for deposits made by stakers.
    function withdrawRewards(address account, uint256 shares, uint256 totalShares) public virtual onlyOperatorStaking {
        address stakingToken_ = stakingToken();
        uint256 totalBalance = IERC20(stakingToken_).balanceOf(address(this));
        uint256 released_ = _released[account];
        uint256 releasable = Math.mulDiv(_totalReleased + totalBalance, shares, totalShares) - released_;
        _totalReleased += releasable;
        _released[account] = released_ + releasable;
        uint256 operatorReward = Math.mulDiv(releasable, _stakersRewardRatio, 100);
        uint256 stakerReward = releasable - operatorReward;
        require(IERC20(stakingToken_).transfer(owner(), operatorReward));
        require(IERC20(stakingToken_).transfer(account, stakerReward));
        emit RewardClaimed(msg.sender, releasable);
    }

    function vituallyWithdrawRewards(
        address account,
        uint256 burnShares,
        uint256 totalShares
    ) public virtual onlyOperatorStaking {
        address stakingToken_ = stakingToken();
        uint256 totalBalance = IERC20(stakingToken_).balanceOf(address(this));
        uint256 virtuallyReleased = Math.mulDiv(_totalReleased + totalBalance, burnShares, totalShares);
        _totalReleased -= virtuallyReleased;
        _released[account] -= virtuallyReleased;
    }
}
