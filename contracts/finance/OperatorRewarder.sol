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
 * A rewarder contract to split rewards between the owner and the stakers.
 */
contract OperatorRewarder is Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 private immutable _token;
    ProtocolStaking private immutable _protocolStaking;
    OperatorStaking private immutable _operatorStaking;
    uint16 private _ownerFeeBasisPoints;
    bool private _shutdown;
    uint256 private _lastAllTimeReward; // last owner reward claim
    uint256 private _ownerPaidReward;
    uint256 private _stakersPaidReward;
    int256 private _stakersVirtualPaidReward;
    mapping(address => int256) private _stakerPaidReward;

    event Shutdown();

    error CallerNotOperatorStaking(address caller);
    error AlreadyShutdown();

    modifier onlyOperatorStaking() {
        require(msg.sender == address(_operatorStaking), CallerNotOperatorStaking(msg.sender));
        _;
    }

    constructor(address owner, ProtocolStaking protocolStaking, OperatorStaking operatorStaking) Ownable(owner) {
        _token = IERC20(protocolStaking.stakingToken());
        _protocolStaking = protocolStaking;
        _operatorStaking = operatorStaking;
    }

    /// @dev Sets the owner basis points fee to `basisPoints`.
    function setOwnerFee(uint16 basisPoints) public virtual onlyOwner {
        claimOwnerReward();
        _ownerFeeBasisPoints = basisPoints;
    }

    /// @dev Shutdowns current rewarder.
    function shutdown() public virtual onlyOperatorStaking {
        require(!_shutdown, AlreadyShutdown());
        _shutdown = true;
        _protocolStaking.claimRewards(address(_operatorStaking));
        emit Shutdown();
    }

    /// @dev Virtually updates reward of `to` and `from` on each transfer.
    function transferHook(address from, address to, uint256 amount) public virtual onlyOperatorStaking {
        uint256 oldTotalSupply = _operatorStaking.totalSupply();
        if (oldTotalSupply == 0) return;

        int256 totalVirtualPaidDiff;
        totalVirtualPaidDiff += _updateRewards(from, -SafeCast.toInt256(amount), oldTotalSupply);
        totalVirtualPaidDiff += _updateRewards(to, SafeCast.toInt256(amount), oldTotalSupply);
        _stakersVirtualPaidReward += totalVirtualPaidDiff;
    }

    /// @dev Claims reward of the owner.
    function claimOwnerReward() public virtual {
        uint256 unpaidReward = ownerUnpaidReward();
        _lastAllTimeReward = allTimeReward();
        if (unpaidReward > 0) {
            _ownerPaidReward += unpaidReward;
            _fetchReward(unpaidReward);
            _token.safeTransfer(owner(), unpaidReward);
        }
    }

    /// @dev Claims reward of a staker.
    function claimStakerReward(address account) public virtual {
        uint256 unpaidReward = stakerUnpaidReward(account);
        if (unpaidReward > 0) {
            _stakerPaidReward[account] += SafeCast.toInt256(unpaidReward);
            _stakersPaidReward += unpaidReward;
            _fetchReward(unpaidReward);
            _token.safeTransfer(account, unpaidReward);
        }
    }

    /// @dev Gets staking token address.
    function token() public view returns (IERC20) {
        return _token;
    }

    /// @dev Gets owner fee basis points.
    function ownerFeeBasisPoints() public view returns (uint16) {
        return _ownerFeeBasisPoints;
    }

    /// @dev Returns true if shutdown.
    function isShutdown() public view returns (bool) {
        return _shutdown;
    }

    /// @dev Gets unpaid reward.
    function unpaidReward() public view returns (uint256) {
        return _token.balanceOf(address(this)) + (_shutdown ? 0 : _protocolStaking.earned(address(_operatorStaking)));
    }

    /// @dev Gets all time reward.
    function allTimeReward() public view virtual returns (uint256) {
        return unpaidReward() + _ownerPaidReward + _stakersPaidReward;
    }

    /// @dev Gets all time reward of owner.
    function ownerAllTimeReward() public view virtual returns (uint256) {
        return ownerUnpaidReward() + _ownerPaidReward;
    }

    /// @dev Gets all time reward of stakers.
    function stakersAllTimeReward() public view virtual returns (uint256) {
        return stakersUnpaidReward() + _stakersPaidReward;
    }

    /// @dev Gets unpaid reward of owner.
    function ownerUnpaidReward() public view virtual returns (uint256) {
        return ((allTimeReward() - _lastAllTimeReward) * ownerFeeBasisPoints()) / 10000;
    }

    /// @dev Gets unpaid reward of stakers.
    function stakersUnpaidReward() public view virtual returns (uint256) {
        return unpaidReward() - ownerUnpaidReward();
    }

    /// @dev Gets unpaid reward of a staker.
    function stakerUnpaidReward(address account) public view virtual returns (uint256) {
        uint256 allocation = _stakerAllocation(_operatorStaking.balanceOf(account), _operatorStaking.totalSupply());
        return SafeCast.toUint256(SafeCast.toInt256(allocation) - _stakerPaidReward[account]);
    }

    /// @dev Gets paid reward of owner.
    function ownerPaidReward() public view virtual returns (uint256) {
        return _ownerPaidReward;
    }

    /// @dev Gets paid reward of stakers.
    function stakersPaidReward() public view virtual returns (uint256) {
        return _stakersPaidReward;
    }

    /// @dev Gets paid reward of staker.
    function stakerPaidReward(address account) public view virtual returns (int256) {
        return _stakerPaidReward[account];
    }

    function _updateRewards(address user, int256 diff, uint256 oldTotalSupply) internal virtual returns (int256) {
        int256 virtualAmount = SafeCast.toInt256(
            _stakerAllocation(SafeCast.toUint256(diff < 0 ? -diff : diff), oldTotalSupply)
        ) * (diff < 0 ? -1 : int256(1));

        if (user != address(0)) {
            _stakerPaidReward[user] += virtualAmount;
        } else {
            return -virtualAmount;
        }
        return 0;
    }

    /// @dev Eventually claims reward on protocol if current contract does not have enough tokens.
    function _fetchReward(uint256 unpaidReward_) private {
        if (unpaidReward_ > _token.balanceOf(address(this))) {
            _protocolStaking.claimRewards(address(_operatorStaking));
        }
    }

    /// @dev Compute allocation of a staker.
    function _stakerAllocation(uint256 share, uint256 total) private view returns (uint256) {
        return
            total > 0
                ? SafeCast.toUint256(SafeCast.toInt256(stakersAllTimeReward()) + _stakersVirtualPaidReward).mulDiv(
                    share,
                    total
                )
                : 0;
    }
}
