// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ProtocolStaking} from "./ProtocolStaking.sol";
import {console} from "hardhat/console.sol";

contract OperatorStaking is ERC4626, Ownable {
    using Checkpoints for Checkpoints.Trace208;

    ProtocolStaking private _protocolStaking;
    uint256 private _totalSharesUnstaking;
    mapping(address => uint256) private _sharesReleased;
    mapping(address => Checkpoints.Trace208) private _unstakeRequests;

    constructor(
        string memory name,
        string memory symbol,
        ProtocolStaking protocolStaking,
        address owner
    ) ERC20(name, symbol) ERC4626(IERC20(protocolStaking.stakingToken())) Ownable(owner) {
        _protocolStaking = protocolStaking;
        IERC20(protocolStaking.stakingToken()).approve(address(protocolStaking), type(uint256).max);
    }

    function restake() public virtual {
        uint256 amountToRestake = IERC20(asset()).balanceOf(address(this)) +
            _protocolStaking.tokensInCooldown(address(this)) -
            previewRedeem(totalSharesUnstaking());
        _protocolStaking.stake(amountToRestake);
    }

    function release(address account) public virtual {
        uint256 sharesToRelease = _unstakeRequests[account].upperLookup(Time.timestamp()) - _sharesReleased[msg.sender];
        if (sharesToRelease > 0) {
            uint256 assets = previewRedeem(sharesToRelease);
            _totalSharesUnstaking -= sharesToRelease;
            SafeERC20.safeTransfer(IERC20(asset()), account, assets);
        }
    }

    /**
     * WARNING: This design only works with a non-negligible cooldown period on `ProtocolStaking` such that the jumps in `totalAssets`
     * upon claiming and disbursing rewards can't be gamed. If the cooldown period is small, `totalAssets` must count unclaimed rewards.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return
            super.totalAssets() +
            _protocolStaking.balanceOf(address(this)) +
            _protocolStaking.tokensInCooldown(address(this));
    }

    function totalSupply() public view virtual override(ERC20, IERC20) returns (uint256) {
        return super.totalSupply() + totalSharesUnstaking();
    }

    function totalSharesUnstaking() public view virtual returns (uint256) {
        return _totalSharesUnstaking;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        super._deposit(caller, receiver, assets, shares);
        _protocolStaking.stake(assets);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);
        _protocolStaking.unstake(address(this), assets);

        (, uint256 lastReleaseTime, uint256 totalRequestedToWithdraw) = _unstakeRequests[receiver].latestCheckpoint();
        uint256 releaseTime = Time.timestamp() + _protocolStaking.unstakeCooldownPeriod();
        _unstakeRequests[receiver].push(
            uint48(Math.max(releaseTime, lastReleaseTime)),
            uint208(totalRequestedToWithdraw + shares)
        );
        _totalSharesUnstaking += shares;
    }
}
