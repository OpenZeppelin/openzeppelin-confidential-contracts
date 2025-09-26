// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ProtocolStaking} from "./ProtocolStaking.sol";

contract OperatorStaking is ERC4626 {
    ProtocolStaking private _protocolStaking;

    constructor(
        string memory name,
        string memory symbol,
        IERC20 asset,
        ProtocolStaking protocolStaking
    ) ERC20(name, symbol) ERC4626(asset) {
        _protocolStaking = protocolStaking;
        asset.approve(address(protocolStaking), type(uint256).max);
    }

    function restake() public virtual {
        _protocolStaking.stake(IERC20(asset()).balanceOf(address(this)));
    }

    function totalAssets() public view virtual override returns (uint256) {
        return super.totalAssets() + _protocolStaking.balanceOf(address(this));
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
        super._withdraw(caller, receiver, owner, assets, shares);
        _protocolStaking.unstake(receiver, assets);
    }
}
