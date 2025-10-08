// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {ProtocolStaking} from "./ProtocolStaking.sol";
import {OperatorStaking} from "./OperatorStaking.sol";
import {console} from "hardhat/console.sol";

contract Rewarder is Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    ProtocolStaking private immutable _protocolStaking;
    OperatorStaking private immutable _operatorStaking;
    uint16 private _ownerFeeBasisPoints;
    bool private _isShutdown = false;
    uint256 _lastFeeClaimedTotalRewards;
    IERC20 private immutable _token;
    uint256 private _totalPaid;
    int256 private _totalVirtualPaid;
    mapping(address => int256) private _paid;

    constructor(address owner, ProtocolStaking protocolStaking, OperatorStaking operatorStaking) Ownable(owner) {
        _protocolStaking = protocolStaking;
        _operatorStaking = operatorStaking;
        _token = IERC20(protocolStaking.stakingToken());
    }

    function claimRewards(address account) public virtual {
        uint256 rewards = earned(account);
        if (rewards > 0) {
            _paid[account] += SafeCast.toInt256(rewards);
            _totalPaid += rewards;

            if (rewards > token().balanceOf(address(this))) {
                _protocolStaking.claimRewards(address(_operatorStaking));
            }
            IERC20(token()).safeTransfer(account, rewards);
        }
    }

    function pendingOwnerFee() public view virtual returns (uint256) {
        uint256 deltaRewards = _totalPaid + unpaidRewards() - _lastFeeClaimedTotalRewards;
        return (deltaRewards * _ownerFeeBasisPoints) / 10000;
    }

    function claimOwnerFee() public virtual {
        uint256 pendingOwnerFee_ = pendingOwnerFee();
        uint256 currentTotalRewards = _totalPaid + unpaidRewards();
        _lastFeeClaimedTotalRewards = currentTotalRewards - pendingOwnerFee_;

        if (pendingOwnerFee_ > token().balanceOf(address(this))) {
            _protocolStaking.claimRewards(address(_operatorStaking));
        }
        IERC20(token()).safeTransfer(owner(), pendingOwnerFee_);
    }

    /// @dev Sets the owner basis points fee to `basisPoints`.
    function setOwnerFee(uint16 basisPoints) public virtual {
        claimOwnerFee();
        _ownerFeeBasisPoints = basisPoints;
    }

    function shutdown() public virtual {
        require(msg.sender == address(_operatorStaking) && _isShutdown == false);
        _isShutdown = true;
        _protocolStaking.claimRewards(address(_operatorStaking));
    }

    function transferHook(address from, address to, uint256 amount) public virtual {
        require(msg.sender == address(_operatorStaking), "Not operator staking");

        uint256 oldTotalSupply = _operatorStaking.totalSupply();
        if (oldTotalSupply == 0) return;

        int256 totalVirtualPaidDiff;
        totalVirtualPaidDiff += _updateRewards(from, -SafeCast.toInt256(amount), oldTotalSupply);
        totalVirtualPaidDiff += _updateRewards(to, SafeCast.toInt256(amount), oldTotalSupply);
        _totalVirtualPaid += totalVirtualPaidDiff;
    }

    function earned(address account) public view virtual returns (uint256) {
        // if stakedBalance == 0, there is a risk of totalSupply == 0. To avoid div by 0 just return 0
        uint256 stakedBalance = _operatorStaking.balanceOf(account);
        uint256 allocation = stakedBalance > 0 ? _allocation(stakedBalance, _operatorStaking.totalSupply()) : 0;
        return SafeCast.toUint256(SafeCast.toInt256(allocation) - _paid[account]);
    }

    function token() public view returns (IERC20) {
        return _token;
    }

    function unpaidRewards() public view returns (uint256) {
        return
            token().balanceOf(address(this)) + (_isShutdown ? 0 : _protocolStaking.earned(address(_operatorStaking)));
    }

    function _updateRewards(address user, int256 diff, uint256 oldTotalSupply) internal virtual returns (int256) {
        int256 virtualAmount = SafeCast.toInt256(
            _allocation(SafeCast.toUint256(diff < 0 ? -diff : diff), oldTotalSupply)
        ) * (diff < 0 ? -1 : int256(1));

        if (user != address(0)) {
            _paid[user] += virtualAmount;
        } else {
            return -virtualAmount;
        }
        return 0;
    }

    function _historicalReward() internal view virtual returns (uint256) {
        uint256 counter = token().balanceOf(address(this)) + _totalPaid;
        if (!_isShutdown) {
            counter += _protocolStaking.earned(address(_operatorStaking));
        }
        counter -= pendingOwnerFee();

        return counter;
    }

    function _allocation(uint256 share, uint256 total) private view returns (uint256) {
        return SafeCast.toUint256(SafeCast.toInt256(_historicalReward()) + _totalVirtualPaid).mulDiv(share, total);
    }
}
