// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IOperatorStaking {
    function asset() external view returns (address);
    function globalRewardsRecipient() external view returns (address);
}

interface IPaymentSplitter {
    function releasable(IERC20 token, address account) external view returns (uint256);
    function release(IERC20 token, address account) external;
}

/**
 * @dev A contract handling reward logic to stakers having deposited tokens on an {OperatorStaking} contract.
 */
contract StakersRewardsRecipient is Ownable {
    IOperatorStaking private _operatorStaking;
    uint256 private _totalReleased;
    mapping(address => uint256) private _released;

    error SenderNotOperatorStaking(address account);

    event HoldersRewardRatioSet(uint256 stakersRewardRatio);
    event RewardClaimed(address account, uint256 amount);

    modifier onlyOperatorStaking() {
        require(msg.sender == address(_operatorStaking), SenderNotOperatorStaking(msg.sender));
        _;
    }

    constructor(address owner, address operatorStaking) Ownable(owner) {
        _operatorStaking = IOperatorStaking(operatorStaking);
    }

    /// @dev Gets staking token.
    function stakingToken() public view virtual returns (IERC20) {
        return IERC20(_operatorStaking.asset());
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
        IERC20 stakingToken_ = stakingToken();
        IPaymentSplitter globalRewardsRecipient = IPaymentSplitter(_operatorStaking.globalRewardsRecipient());
        if (globalRewardsRecipient.releasable(stakingToken_, address(this)) > 0) {
            globalRewardsRecipient.release(stakingToken_, address(this));
        }
        uint256 totalBalance = stakingToken_.balanceOf(address(this));
        uint256 released_ = _released[account];
        uint256 releasable = (totalShares > 0 ? Math.mulDiv(_totalReleased + totalBalance, shares, totalShares) : 0) -
            released_;
        _totalReleased += releasable;
        _released[account] = released_ + releasable;
        require(stakingToken_.transfer(account, releasable));
        emit RewardClaimed(account, releasable);
    }

    function increaseReleasedRewards(
        address account,
        uint256 addedShares,
        uint256 totalShares
    ) public virtual onlyOperatorStaking {
        uint256 totalBalance = stakingToken().balanceOf(address(this));
        uint256 virtuallyReleased = totalShares > 0
            ? Math.mulDiv(_totalReleased + totalBalance, addedShares, totalShares)
            : 0;
        _totalReleased += virtuallyReleased;
        _released[account] += virtuallyReleased;
    }

    function decreaseReleasedRewards(
        address account,
        uint256 burnShares,
        uint256 totalShares
    ) public virtual onlyOperatorStaking {
        uint256 totalBalance = stakingToken().balanceOf(address(this));
        uint256 virtuallyReleased = totalShares > 0
            ? Math.mulDiv(_totalReleased + totalBalance, burnShares, totalShares)
            : 0;
        _totalReleased -= virtuallyReleased;
        _released[account] -= virtuallyReleased;
    }
}
