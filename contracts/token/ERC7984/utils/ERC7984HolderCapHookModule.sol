// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984Rwa} from "./../../../interfaces/IERC7984Rwa.sol";
import {ERC7984HookModule} from "./ERC7984HookModule.sol";

/**
 * @dev An ERC-7984 hook module that limits the number of holders for a given token.
 *
 * NOTE: This module must be installed prior to minting any tokens. After the total supply is initialized,
 * it is not possible to guarantee that the number of holders is 0, so the module can not be installed.
 *
 * WARNING: This module may not function correctly with non-standard tokens such as fee on transfer.
 */
abstract contract ERC7984HolderCapHookModule is ERC7984HookModule {
    /// @dev Emitted when the max holder count for a given token is set.
    event ERC7984HolderCapHookModuleMaxHolderCountSet(address indexed token, uint64 newMaxHolderCount);

    /// @dev The new max holder count `maxHolderCount` is invalid.
    error ERC7984HolderCapHookModuleInvalidMaxHolderCount(uint64 maxHolderCount);

    /**
     * The total supply of the token is already initialized.
     * This module must be installed before the total supply is initialized.
     */
    error ERC7984HolderCapHookModuleTotalSupplyInitialized();

    mapping(address => uint64) private _maxHolderCounts;
    mapping(address => euint64) private _holderCounts;

    /**
     * @dev Sets the max number of holders for the given token `token` to `maxHolderCount_`.
     *
     * `msg.sender` must have the agent role on `token`
     **/
    function setMaxHolderCount(address token, uint64 maxHolderCount_) public virtual {
        require(IERC7984Rwa(token).isAgent(msg.sender), ERC7984HookModuleUnauthorizedAccount(msg.sender));
        _setMaxHolderCount(token, maxHolderCount_);
    }

    /// @dev Gets max number of holders for the given token `token`.
    function maxHolderCount(address token) public view virtual returns (uint64) {
        return _maxHolderCounts[token];
    }

    /// @dev Gets current number of holders for the given token `token`.
    function holderCount(address token) public view virtual returns (euint64) {
        return _holderCounts[token];
    }

    /// @inheritdoc ERC7984HookModule
    function _isModuleInstalled(address token) internal view virtual override returns (bool) {
        return _maxHolderCounts[token] != 0;
    }

    /// @dev Sets the max holder count for a given token to `maxHolderCount_` and emits an event.
    function _setMaxHolderCount(address token, uint64 maxHolderCount_) internal {
        require(maxHolderCount_ != 0, ERC7984HolderCapHookModuleInvalidMaxHolderCount(maxHolderCount_));
        _maxHolderCounts[token] = maxHolderCount_;
        emit ERC7984HolderCapHookModuleMaxHolderCountSet(token, maxHolderCount_);
    }

    /// @inheritdoc ERC7984HookModule
    function _preTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool) {
        if (to == address(0) || to == from) {
            return FHE.asEbool(true);
        }

        euint64 fromBalance = IERC7984Rwa(token).confidentialBalanceOf(from);
        euint64 toBalance = IERC7984Rwa(token).confidentialBalanceOf(to);

        _accessHandle(token, fromBalance);
        _accessHandle(token, toBalance);

        euint64 encryptedZero = FHE.asEuint64(0);

        euint64 adjustedHolderCount = holderCount(token);
        if (from != address(0)) {
            adjustedHolderCount = FHE.sub(adjustedHolderCount, FHE.asEuint64(FHE.eq(fromBalance, encryptedAmount)));
        }

        return
            FHE.or(
                FHE.eq(encryptedAmount, encryptedZero), // zero transfer
                FHE.or(
                    FHE.ne(toBalance, encryptedZero), // already a holder
                    FHE.lt(adjustedHolderCount, maxHolderCount(token)) // room for another holder
                )
            );
    }

    /// @inheritdoc ERC7984HookModule
    function _postTransfer(address token, address from, address to, euint64 encryptedAmount) internal virtual override {
        super._postTransfer(token, from, to, encryptedAmount);

        if (from == to) return;

        euint64 fromBalance = IERC7984Rwa(token).confidentialBalanceOf(from);
        euint64 toBalance = IERC7984Rwa(token).confidentialBalanceOf(to);

        _accessHandle(token, fromBalance);
        _accessHandle(token, toBalance);

        euint64 encryptedZero = FHE.asEuint64(0);
        ebool transferNotZero = FHE.ne(encryptedAmount, encryptedZero);
        euint64 newHolderCount = holderCount(token);

        if (to != address(0)) {
            ebool addHolder = FHE.and(transferNotZero, FHE.eq(toBalance, encryptedAmount));
            newHolderCount = FHE.add(newHolderCount, FHE.asEuint64(addHolder));
        }

        if (from != address(0)) {
            ebool subHolder = FHE.and(transferNotZero, FHE.eq(fromBalance, encryptedZero));
            newHolderCount = FHE.sub(newHolderCount, FHE.asEuint64(subHolder));
        }

        _holderCounts[token] = newHolderCount;
        FHE.allowThis(newHolderCount);
    }

    /**
     * @dev See {ERC7984HookModule-_onInstall}. The `initData` must contain the initial max holder count for the token
     * as a standard ABI encoded uint64.
     **/
    function _onInstall(address token, bytes calldata initData) internal virtual override {
        require(
            !FHE.isInitialized(IERC7984Rwa(token).confidentialTotalSupply()),
            ERC7984HolderCapHookModuleTotalSupplyInitialized()
        );

        super._onInstall(token, initData);

        uint64 maxHolderCount_ = abi.decode(initData, (uint64));
        _setMaxHolderCount(token, maxHolderCount_);
    }

    function _onUninstall(address token, bytes calldata deinitData) internal virtual override {
        super._onUninstall(token, deinitData);
        delete _maxHolderCounts[token];
        _holderCounts[token] = euint64.wrap(0);
    }
}
