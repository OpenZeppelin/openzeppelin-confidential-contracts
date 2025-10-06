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

contract Rewarder is Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    ProtocolStaking private immutable _protocolStaking;
    OperatorStaking private immutable _operatorStaking;
    IERC20 private immutable _token;
    uint256 private _totalPaid;
    bool private _isShutdown = false;
    int256 private _totalVirtualPaid;
    mapping(address => int256) private _paid;

    constructor(address owner, ProtocolStaking protocolStaking, OperatorStaking operatorStaking) Ownable(owner) {
        _protocolStaking = protocolStaking;
        _operatorStaking = operatorStaking;
    }

    function claimRewards(address account) public virtual {
        uint256 rewards = earned(account);
        if (rewards > 0) {
            if (rewards > token().balanceOf(address(this))) {
                _protocolStaking.claimRewards(address(_operatorStaking));
            }

            _paid[account] += SafeCast.toInt256(rewards);
            _totalPaid += rewards;
            IERC20(token()).safeTransfer(account, rewards);
        }
    }

    function transferHook(address from, address to, uint256 amount) public virtual {
        require(msg.sender == address(_operatorStaking));
        _updateRewards(from, -SafeCast.toInt256(amount));
        _updateRewards(to, SafeCast.toInt256(amount));
    }

    function shutdown() public virtual {
        require(msg.sender == address(_operatorStaking) && _isShutdown == false);
        _isShutdown = true;
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

    function _updateRewards(address user, int256 diff) internal virtual {
        int256 virtualAmount = SafeCast.toInt256(
            _allocation(SafeCast.toUint256(diff < 0 ? -diff : diff), _operatorStaking.totalSupply())
        );
        if (diff < 0) {
            _paid[user] -= virtualAmount;
            _totalVirtualPaid -= virtualAmount;
        } else {
            _paid[user] += virtualAmount;
            _totalVirtualPaid += virtualAmount;
        }
    }

    function _historicalReward() internal view virtual returns (uint256) {
        uint256 counter = token().balanceOf(address(this)) + _totalPaid;
        if (!_isShutdown) {
            counter += _protocolStaking.earned(address(_operatorStaking));
        }

        return counter;
    }

    function _allocation(uint256 share, uint256 total) private view returns (uint256) {
        return SafeCast.toUint256(SafeCast.toInt256(_historicalReward()) + _totalVirtualPaid).mulDiv(share, total);
    }
}
