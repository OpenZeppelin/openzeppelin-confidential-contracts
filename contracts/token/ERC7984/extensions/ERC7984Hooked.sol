// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {LowLevelCall} from "@openzeppelin/contracts/utils/LowLevelCall.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC7984HookModule} from "./../../../interfaces/IERC7984HookModule.sol";
import {HandleAccessManager} from "./../../../utils/HandleAccessManager.sol";
import {ERC7984} from "./../ERC7984.sol";

/**
 * @dev Extension of {ERC7984} that supports hook modules. Inspired by ERC-7579 modules.
 *
 * Modules are called before and after transfers. Before the transfer, modules
 * conduct checks to see if they approve the given transfer and return an encrypted boolean. If any module
 * returns false, the transferred amount becomes 0. After the transfer, modules are notified of the final transfer
 * amount and may do accounting as necessary. Modules may revert on either call, which will propagate
 * and revert the entire transaction.
 *
 * NOTE: Hook modules are trusted contracts--they have access to any private state the token has access to.
 */
abstract contract ERC7984Hooked is ERC7984, HandleAccessManager {
    using EnumerableSet for *;

    EnumerableSet.AddressSet private _modules;

    /// @dev Emitted when a module is installed.
    event ModuleInstalled(address module);
    /// @dev Emitted when a module is uninstalled.
    event ModuleUninstalled(address module);

    /// @dev The address is not a valid module.
    error ERC7984HookedInvalidModule(address module);
    /// @dev The module is already installed.
    error ERC7984HookedDuplicateModule(address module);
    /// @dev The module is not installed.
    error ERC7984HookedNonexistentModule(address module);
    /// @dev The maximum number of modules has been exceeded.
    error ERC7984HookedExceededMaxModules();

    /// @dev Checks if a module is installed.
    function isModuleInstalled(address module) public view virtual returns (bool) {
        return _modules.contains(module);
    }

    /**
     * @dev Installs a hook module.
     *
     * Consider gas footprint of the module before adding it since all modules will perform
     * all steps (pre-check, check, post-hook) in a single transaction.
     */
    function installModule(address module, bytes memory initData) public virtual onlyModuleChange {
        _installModule(module, initData);
    }

    /// @dev Uninstalls a hook module.
    function uninstallModule(address module, bytes memory deinitData) public virtual onlyModuleChange {
        _uninstallModule(module, deinitData);
    }

    /// @dev Returns the list of modules installed on the token.
    function modules() public view virtual returns (address[] memory) {
        return _modules.values();
    }

    /// @dev Returns the maximum number of modules that can be installed.
    function maxModules() public view virtual returns (uint256) {
        return 15;
    }

    /// @dev Authorization logic for installing and uninstalling modules. Must be implemented by the concrete contract.
    function _authorizeModuleChange() internal virtual;

    /// @dev Internal function which installs a hook module.
    function _installModule(address module, bytes memory initData) internal virtual {
        require(_modules.length() < maxModules(), ERC7984HookedExceededMaxModules());
        require(
            ERC165Checker.supportsInterface(module, type(IERC7984HookModule).interfaceId),
            ERC7984HookedInvalidModule(module)
        );
        require(_modules.add(module), ERC7984HookedDuplicateModule(module));

        IERC7984HookModule(module).onInstall(initData);

        emit ModuleInstalled(module);
    }

    /// @dev Internal function which uninstalls a module.
    function _uninstallModule(address module, bytes memory deinitData) internal virtual {
        require(_modules.remove(module), ERC7984HookedNonexistentModule(module));

        LowLevelCall.callNoReturn(module, abi.encodeCall(IERC7984HookModule.onUninstall, (deinitData)));

        emit ModuleUninstalled(module);
    }

    /**
     * @dev See {ERC7984-_update}.
     *
     * Modified to run pre and post transfer hooks. Zero tokens are transferred if a module does not approve
     * the transfer.
     */
    function _update(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual override returns (euint64 transferred) {
        euint64 amountToTransfer = FHE.select(
            _runPreTransferHooks(from, to, encryptedAmount),
            encryptedAmount,
            FHE.asEuint64(0)
        );
        transferred = super._update(from, to, amountToTransfer);
        _runPostTransferHooks(from, to, transferred);
    }

    /// @dev Runs the pre-transfer hooks for all modules.
    function _runPreTransferHooks(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual returns (ebool compliant) {
        address[] memory modules_ = modules();
        uint256 modulesLength = modules_.length;
        compliant = FHE.asEbool(true);
        for (uint256 i = 0; i < modulesLength; i++) {
            if (FHE.isInitialized(encryptedAmount)) FHE.allowTransient(encryptedAmount, modules_[i]);
            compliant = FHE.and(compliant, IERC7984HookModule(modules_[i]).preTransfer(from, to, encryptedAmount));
        }
    }

    /// @dev Runs the post-transfer hooks for all modules.
    function _runPostTransferHooks(address from, address to, euint64 encryptedAmount) internal virtual {
        address[] memory modules_ = modules();
        uint256 modulesLength = modules_.length;
        for (uint256 i = 0; i < modulesLength; i++) {
            if (FHE.isInitialized(encryptedAmount)) FHE.allowTransient(encryptedAmount, modules_[i]);
            IERC7984HookModule(modules_[i]).postTransfer(from, to, encryptedAmount);
        }
    }

    /// @dev See {HandleAccessManager-_validateHandleAllowance}. Allow modules to access any handle the token has access to.
    function _validateHandleAllowance(bytes32) internal view override returns (bool) {
        return _modules.contains(msg.sender);
    }
}
