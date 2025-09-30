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
 * @dev A contract handling reward logic to holders having deposited tokens on an {OperatorStaking} contract.
 */
contract OperatorStakingRewarder is Ownable {
    address private immutable _operatorStaking;
    uint256 private _holdersRewardRatio = 50;
    uint256 private _totalReleased;
    mapping(address => uint256) private _released;

    error SenderNotOperatorStaking(address account);

    event HoldersRewardRatioSet(uint256 holdersRewardRatio);
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

    /// @dev
    function released(address account) public view virtual returns (uint256) {
        return _released[account];
    }

    /// @dev Claim rewards for deposits made by holders.
    function withdrawRewards(address account) public virtual {
        address stakingToken_ = stakingToken();
        uint256 totalBalance = IERC20(stakingToken_).balanceOf(address(this));
        uint256 released_ = _released[account];
        uint256 releasable; // (totalReleased + totalBalance) * ratio = released + releasable
        if (account == owner()) {
            // releasable = (totalReleased + totalBalance) * ownerRatio - released
            releasable = Math.mulDiv(_totalReleased + totalBalance, operatorRewardRatio(), 100) - released_;
        } else {
            uint256 shares = IERC20(_operatorStaking).balanceOf(account);
            uint256 totalShares = IERC20(_operatorStaking).totalSupply();
            releasable =
                Math.mulDiv(_totalReleased + totalBalance, _holdersRewardRatio * shares, 100 * totalShares) -
                released_; // releasable = (totalReleased + totalBalance) * holdersRatio * (shares / totalShares) - released
        }
        _totalReleased += releasable;
        _released[account] = released_ + releasable;
        require(IERC20(stakingToken_).transfer(account, releasable));
        emit RewardClaimed(msg.sender, releasable);
    }
}
