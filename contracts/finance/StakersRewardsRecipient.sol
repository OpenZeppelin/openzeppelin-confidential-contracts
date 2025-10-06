// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IProtocolStaking {
    function claimRewards(address account) external;
}

interface IOperatorStaking {
    function asset() external view returns (address);
    function protocolStaking() external view returns (address);
    function globalRewardsRecipient() external view returns (address);
}

interface IPaymentSplitter {
    function releasable(IERC20 token, address account) external view returns (uint256);
    function release(IERC20 token, address account) external;
}

/**
 * @dev A contract handling reward logic to stakers having deposited tokens on an {OperatorStaking} contract.
 * Rewards are pulled from a global {IPaymentSplitter} in charge of performing the split between the operator and stakers.
 */
contract StakersRewardsRecipient is Ownable {
    using SafeERC20 for IERC20;

    IOperatorStaking private _operatorStaking;
    uint256 private _totalReleased;
    mapping(address => uint256) private _released;

    event HoldersRewardRatioSet(uint256 stakersRewardRatio);
    event RewardWithdrawn(address account, uint256 amount);

    error SenderNotOperatorStaking(address account);

    modifier onlyOperatorStaking() {
        require(msg.sender == address(_operatorStaking), SenderNotOperatorStaking(msg.sender));
        _;
    }

    modifier pullRewards() {
        _pullRewards();
        _;
    }

    constructor(address owner, address operatorStaking) Ownable(owner) {
        _operatorStaking = IOperatorStaking(operatorStaking);
    }

    /// @dev Gets staking token.
    function stakingToken() public view virtual returns (IERC20) {
        return IERC20(_operatorStaking.asset());
    }

    /// @dev Gets total released tokens.
    function totalReleased() public view virtual returns (uint256) {
        return _totalReleased;
    }

    /// @dev Gets released tokens of an account.
    function released(address account) public view virtual returns (uint256) {
        return _released[account];
    }

    /// @dev Gets releasable tokens of an account. It is recommended to call {pullRewards} before.
    function releaseable(address account) public view virtual returns (uint256) {
        return
            _allocation(
                IERC20(address(_operatorStaking)).balanceOf(account),
                IERC20(address(_operatorStaking)).totalSupply()
            ) - _released[account];
    }

    /// @dev Withdraw rewards of a staker account.
    function withdrawRewards(
        address account,
        uint256 shares,
        uint256 totalShares
    ) public virtual onlyOperatorStaking pullRewards {
        uint256 released_ = _released[account];
        uint256 releasable = _allocation(shares, totalShares) - released_;
        _totalReleased += releasable;
        _released[account] = released_ + releasable;
        stakingToken().safeTransfer(account, releasable);
        emit RewardWithdrawn(account, releasable);
    }

    /// @dev Virtually increases account released rewards when shares are mint for an account.
    function increaseReleasedRewards(
        address account,
        uint256 addedShares,
        uint256 totalShares
    ) public virtual onlyOperatorStaking pullRewards {
        uint256 virtuallyReleased = _allocation(addedShares, totalShares);
        _totalReleased += virtuallyReleased;
        _released[account] += virtuallyReleased;
    }

    /// @dev Virtually decreases account released rewards when shares are burn for an account.
    function decreaseReleasedRewards(
        address account,
        uint256 burnShares,
        uint256 totalShares
    ) public virtual onlyOperatorStaking pullRewards {
        uint256 virtuallyReleased = _allocation(burnShares, totalShares);
        _totalReleased -= virtuallyReleased;
        _released[account] -= virtuallyReleased;
    }

    /// @dev Pull all rewards from global rewards recipient.
    function _pullRewards() internal virtual {
        // Transfer global rewards to the global rewards recipient contract
        IProtocolStaking(_operatorStaking.protocolStaking()).claimRewards((address(_operatorStaking)));
        IERC20 stakingToken_ = stakingToken();
        IPaymentSplitter globalRewardsRecipient = IPaymentSplitter(_operatorStaking.globalRewardsRecipient());
        if (globalRewardsRecipient.releasable(stakingToken_, address(this)) > 0) {
            // Transfer stakers rewards to this stakers rewards recipient contract
            globalRewardsRecipient.release(stakingToken_, address(this));
        }
    }

    /// @dev Gets rewards allocation of a staker. It is recommended to call {pullRewards} before.
    function _allocation(uint256 shares, uint256 totalShares) internal view virtual returns (uint256) {
        return (
            totalShares > 0
                ? Math.mulDiv(_totalReleased + stakingToken().balanceOf(address(this)), shares, totalShares)
                : 0
        );
    }
}
