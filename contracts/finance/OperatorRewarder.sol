// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {OperatorStaking} from "./OperatorStaking.sol";
import {ProtocolStaking} from "./ProtocolStaking.sol";

/**
 * @dev A rewarder contract to split rewards between the owner and the stakers.
 */
contract OperatorRewarder is Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 private immutable _token;
    ProtocolStaking private immutable _protocolStaking;
    OperatorStaking private immutable _operatorStaking;
    uint16 private _ownerFeeBasisPoints;
    bool private _shutdown;
    uint256 private _lastClaimTotalAssetsPlusPaidRewards;
    uint256 private _totalRewardsPaid;
    int256 private _totalVirtualRewardsPaid;
    mapping(address => int256) private _rewardsPaid;

    event Shutdown();
    event OwnerFeeUpdated(uint16 oldFee, uint16 newFee);

    error CallerNotOperatorStaking(address caller);
    error AlreadyShutdown();
    error InvalidBasisPoints(uint16 basisPoints);

    modifier onlyOperatorStaking() {
        require(msg.sender == address(operatorStaking()), CallerNotOperatorStaking(msg.sender));
        _;
    }

    constructor(address owner, ProtocolStaking protocolStaking_, OperatorStaking operatorStaking_) Ownable(owner) {
        _token = IERC20(protocolStaking_.stakingToken());
        _protocolStaking = protocolStaking_;
        _operatorStaking = operatorStaking_;
    }

     /// @dev Claims reward of a staker.
    function claimRewards(address account) public virtual {
        uint256 earned_ = earned(account);
        if (earned_ > 0) {
            _rewardsPaid[account] += SafeCast.toInt256(earned_);
            _totalRewardsPaid += earned_;
            _doTransferOut(account, earned_);
        }
    }

    /// @dev Claims owner fee.
    function claimOwnerFee() public virtual {
        uint256 unpaidOwnerFee_ = unpaidOwnerFee();
        _lastClaimTotalAssetsPlusPaidRewards = _totalAssetsPlusPaidRewards() - unpaidOwnerFee_;
        if (unpaidOwnerFee_ > 0) {
            _doTransferOut(owner(), unpaidOwnerFee_);
        }
    }

    /// @dev Sets the owner basis points fee to `basisPoints`.
    function setOwnerFee(uint16 basisPoints) public virtual onlyOwner {
        require(basisPoints <= 10000, InvalidBasisPoints(basisPoints));

        claimOwnerFee();
        emit OwnerFeeUpdated(_ownerFeeBasisPoints, basisPoints);
        _ownerFeeBasisPoints = basisPoints;
    }

    /// @dev Shutdowns current rewarder.
    function shutdown() public virtual onlyOperatorStaking {
        require(!_shutdown, AlreadyShutdown());
        _shutdown = true;
        _protocolStaking.claimRewards(address(operatorStaking()));
        emit Shutdown();
    }

    /// @dev Virtually updates reward of `to` and `from` on each transfer.
    function transferHook(address from, address to, uint256 shares) public virtual onlyOperatorStaking {
        uint256 oldTotalSupply = operatorStaking().totalSupply();
        if(oldTotalSupply == 0) return;

        int256 virtualAmount = SafeCast.toInt256(_allocation(shares, oldTotalSupply));
        int256 totalVirtualRewardsPaid = _totalVirtualRewardsPaid;

        if (from != address(0)) {
            _rewardsPaid[from] -= virtualAmount;
            totalVirtualRewardsPaid -= virtualAmount;
        } else {
            totalVirtualRewardsPaid += virtualAmount;
        }

        if (to != address(0)) {
            _rewardsPaid[to] += virtualAmount;
        } else {
            totalVirtualRewardsPaid -= virtualAmount;
        }
        _totalVirtualRewardsPaid = totalVirtualRewardsPaid;
    }

    /// @dev Gets staking token address.
    function token() public view returns (IERC20) {
        return _token;
    }

    function protocolStaking() public view returns (ProtocolStaking) {
        return _protocolStaking;
    }

    function operatorStaking() public view returns (OperatorStaking) {
        return _operatorStaking;
    }

    /// @dev Returns true if shutdown.
    function isShutdown() public view returns (bool) {
        return _shutdown;
    }

    /// @dev Gets owner fee basis points.
    function ownerFeeBasisPoints() public view returns (uint16) {
        return _ownerFeeBasisPoints;
    }

    /// @dev Gets unpaid reward of a staker.
    function earned(address account) public view virtual returns (uint256) {
        uint256 stakedBalance = operatorStaking().balanceOf(account);
        int256 allocation = SafeCast.toInt256(stakedBalance > 0 ? _allocation(stakedBalance, operatorStaking().totalSupply()) : 0);
        int256 paid = _rewardsPaid[account];
        if(paid >= allocation) {
            return 0;
        }
        return SafeCast.toUint256(allocation - paid);
    }

    /// @dev Gets unpaid reward of owner.
    function unpaidOwnerFee() public view virtual returns (uint256) {
       return _unpaidOwnerFee(_totalAssetsPlusPaidRewards());
    }

    function _doTransferOut(address to, uint256 amount) internal {
        if (amount > token().balanceOf(address(this))) {
            protocolStaking().claimRewards(address(_operatorStaking));
        }
        token().safeTransfer(to, amount);
    }

    function _totalAssetsPlusPaidRewards() internal view returns (uint256) {
        return token().balanceOf(address(this)) + (isShutdown() ? 0 : protocolStaking().earned(address(operatorStaking()))) + _totalRewardsPaid;
    }

    function _historicalReward() internal view returns (uint256) {
        uint256 totalAssetsPlusPaidRewards = _totalAssetsPlusPaidRewards();
        return totalAssetsPlusPaidRewards - _unpaidOwnerFee(totalAssetsPlusPaidRewards);
    }

    function _unpaidOwnerFee(uint256 totalAssetsPlusPaidRewards) internal view returns (uint256) {
        uint256 totalAssetsPlusPaidRewardsDelta = totalAssetsPlusPaidRewards - _lastClaimTotalAssetsPlusPaidRewards;
        return totalAssetsPlusPaidRewardsDelta * ownerFeeBasisPoints() / 10_000;
    }

    /// @dev Compute total allocation based on number of shares and total shares. Must take paid rewards into account after.
    function _allocation(uint256 share, uint256 total) private view returns (uint256) {
        return SafeCast.toUint256(SafeCast.toInt256(_historicalReward()) + _totalVirtualRewardsPaid).mulDiv(share, total);
    }
}
