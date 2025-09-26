// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @dev A contract handling reward logic to holders having deposited tokens on an {OperatorStaking} contract.
 */
contract OperatorStakingRewarder is Ownable {
    address private immutable _operatorStaking;
    uint256 private _holdersRewardRatio = 50;
    uint256 private _totalReleased;
    mapping(address => uint256) private _released;

    event HoldersRewardRatioSet(uint256 holdersRewardRatio);
    event RewardClaimed(address account, uint256 amount);

    constructor(address owner, address operatorStaking) Ownable(owner) {
        _operatorStaking = operatorStaking;
    }

    /// @dev Gets staking token.
    function stakingToken() public view virtual returns (address) {
        return IERC4626(_operatorStaking).asset();
    }

    /// @dev Gets reward ratio for all holders.
    function holdersRewardRatio() public view virtual returns (uint256) {
        return _holdersRewardRatio;
    }

    /// @dev Gets reward ratio for operator.
    function operatorRewardRatio() public view virtual returns (uint256) {
        return 100 - _holdersRewardRatio;
    }

    /// @dev Sets reward ratio for all holders.
    function setHoldersRewardRatio(uint256 holdersRewardRatio_) public virtual onlyOwner {
        _holdersRewardRatio = holdersRewardRatio_;
        emit HoldersRewardRatioSet(holdersRewardRatio_);
    }

    /// @dev Claim rewards for deposits made by holders.
    function claim(address account) public virtual {
        uint256 ratio;
        if (account == owner()) {
            ratio = operatorRewardRatio();
        } else {
            uint256 shares = IERC4626(_operatorStaking).balanceOf(account);
            uint256 totalShares = IERC4626(_operatorStaking).totalSupply();
            ratio = Math.mulDiv(_holdersRewardRatio, shares, totalShares);
        }
        address stakingToken_ = stakingToken();
        uint256 balance = IERC20(stakingToken_).balanceOf(address(this));
        uint256 released = _released[account];
        // (totalReleased + balance) * ratio = released + releasable
        uint256 releasable = Math.mulDiv(_totalReleased + balance, ratio, 100) - released;
        _totalReleased += releasable;
        _released[account] = released + releasable;
        require(IERC20(stakingToken_).transfer(account, releasable));
        emit RewardClaimed(msg.sender, releasable);
    }
}
