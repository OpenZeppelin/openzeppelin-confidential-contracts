// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984Rwa} from "./../../../interfaces/IERC7984Rwa.sol";
import {FHESafeMath} from "./../../../utils/FHESafeMath.sol";
import {ERC7984HookModule} from "./ERC7984HookModule.sol";

/**
 * @dev An ERC-7984 hook module that limits the balance of each investor.
 *
 * This module is compatible with {ERC7984Hooked}.
 */
abstract contract ERC7984BalanceCapHookModule is ERC7984HookModule {
    /// @dev Emitted when the max balance for a given token is set.
    event ERC7984BalanceCapHookModuleMaxBalanceSet(address token, uint64 newMaxBalance);

    mapping(address => uint64) private _maxBalances;

    /// @dev See {ERC7984HookModule-onInstall}. The `initData` should contain the initial max balance for the token.
    function onInstall(bytes calldata initData) public override {
        uint64 maxBalance_ = abi.decode(initData, (uint64));
        _setMaxBalance(msg.sender, maxBalance_);

        super.onInstall(initData);
    }

    /**
     * @dev Sets the max balance for a given token `token` to `maxBalance_`.
     *
     * `msg.sender` must have the agent role on `token`
     **/
    function setMaxBalance(address token, uint64 maxBalance_) public virtual {
        require(IERC7984Rwa(token).isAgent(msg.sender), ERC7984HookModuleUnauthorizedAccount(msg.sender));
        _setMaxBalance(token, maxBalance_);
    }

    /// @dev Gets the max balance for a given token `token`.
    function maxBalance(address token) public view virtual returns (uint64) {
        return _maxBalances[token];
    }

    /// @dev Sets the max balance for a given token to `maxBalance` and emits an event.
    function _setMaxBalance(address token, uint64 maxBalance_) internal {
        _maxBalances[token] = maxBalance_;

        emit ERC7984BalanceCapHookModuleMaxBalanceSet(token, maxBalance_);
    }

    /// @inheritdoc ERC7984HookModule
    function _preTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool) {
        if (to == address(0) || from == to) {
            return FHE.asEbool(true);
        }

        euint64 balance = IERC7984Rwa(token).confidentialBalanceOf(to);
        _getTokenHandleAllowance(token, balance);

        if (FHE.isInitialized(balance))
            require(FHE.isAllowed(balance, token), ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(balance, token));

        (ebool increased, euint64 futureBalance) = FHESafeMath.tryIncrease(balance, encryptedAmount);
        return FHE.and(increased, FHE.le(futureBalance, maxBalance(token)));
    }
}
