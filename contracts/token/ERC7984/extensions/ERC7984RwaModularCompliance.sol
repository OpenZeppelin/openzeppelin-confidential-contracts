// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {LowLevelCall} from "@openzeppelin/contracts/utils/LowLevelCall.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IComplianceModuleConfidential} from "./../../../interfaces/IComplianceModuleConfidential.sol";
import {IERC7984RwaModularCompliance} from "./../../../interfaces/IERC7984Rwa.sol";
import {HandleAccessManager} from "./../../../utils/HandleAccessManager.sol";
import {ERC7984Rwa} from "./ERC7984Rwa.sol";

/**
 * @dev Extension of {ERC7984Rwa} that supports compliance modules for confidential Real World Assets (RWAs).
 * Inspired by ERC-7579 modules.
 *
 * Compliance modules are called before transfers and after transfers. Before the transfer, compliance modules
 * conduct checks to see if they approve the given transfer and return an encrypted boolean. If any module
 * returns false, the transferred amount becomes 0. After the transfer, modules are notified of the final transfer
 * amount and may do accounting as necessary. Compliance modules may revert on either call, which will propagate
 * and revert the entire transaction.
 *
 * NOTE: Force transfers bypass the compliance checks before the transfer. All transfers call compliance modules after the transfer.
 */
abstract contract ERC7984RwaModularCompliance is ERC7984Rwa, IERC7984RwaModularCompliance, HandleAccessManager {
    using EnumerableSet for *;

    EnumerableSet.AddressSet private _complianceModules;

    /// @dev Emitted when a module is installed.
    event ModuleInstalled(address module);
    /// @dev Emitted when a module is uninstalled.
    event ModuleUninstalled(address module);

    /// @dev The address is not a valid compliance module.
    error ERC7984RwaInvalidModule(address module);
    /// @dev The module is already installed.
    error ERC7984RwaDuplicateModule(address module);
    /// @dev The module is not installed.
    error ERC7984RwaNonexistentModule(address module);
    /// @dev The maximum number of modules has been exceeded.
    error ERC7984RwaExceededMaxModules();

    /// @inheritdoc IERC7984RwaModularCompliance
    function isModuleInstalled(address module) public view virtual returns (bool) {
        return _complianceModules.contains(module);
    }

    /**
     * @inheritdoc IERC7984RwaModularCompliance
     * @dev Consider gas footprint of the module before adding it since all modules will perform
     * all steps (pre-check, compliance check, post-hook) in a single transaction.
     */
    function installModule(address module, bytes memory initData) public virtual onlyAdmin {
        _installModule(module, initData);
    }

    /// @inheritdoc IERC7984RwaModularCompliance
    function uninstallModule(address module, bytes memory deinitData) public virtual onlyAdmin {
        _uninstallModule(module, deinitData);
    }

    /// @dev Returns the maximum number of modules that can be installed.
    function maxComplianceModules() public view virtual returns (uint256) {
        return 15;
    }

    /// @inheritdoc ERC7984Rwa
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC7984RwaModularCompliance).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Internal function which installs a transfer compliance module.
    function _installModule(address module, bytes memory initData) internal virtual {
        require(_complianceModules.length() < maxComplianceModules(), ERC7984RwaExceededMaxModules());
        require(
            ERC165Checker.supportsInterface(module, type(IComplianceModuleConfidential).interfaceId),
            ERC7984RwaInvalidModule(module)
        );
        require(_complianceModules.add(module), ERC7984RwaDuplicateModule(module));

        IComplianceModuleConfidential(module).onInstall(initData);

        emit ModuleInstalled(module);
    }

    /// @dev Internal function which uninstalls a compliance module.
    function _uninstallModule(address module, bytes memory deinitData) internal virtual {
        require(_complianceModules.remove(module), ERC7984RwaNonexistentModule(module));

        // ignore success purposely to avoid modules that revert on uninstall
        LowLevelCall.callNoReturn(module, abi.encodeCall(IComplianceModuleConfidential.onUninstall, (deinitData)));

        emit ModuleUninstalled(module);
    }

    /**
     * @dev Updates confidential balances. It transfers zero if it does not follow
     * transfer compliance. Runs hooks after the transfer.
     */
    function _update(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual override returns (euint64 transferred) {
        euint64 amountToTransfer = FHE.select(
            _checkCompliance(from, to, encryptedAmount),
            encryptedAmount,
            FHE.asEuint64(0)
        );
        transferred = super._update(from, to, amountToTransfer);
        _postTransferCompliance(from, to, transferred);
    }

    /**
     * @dev Forces the update of confidential balances. Bypasses compliance checks
     * before the transfer. Runs hooks after the force transfer.
     */
    function _forceUpdate(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual override returns (euint64 transferred) {
        transferred = super._forceUpdate(from, to, encryptedAmount);
        _postTransferCompliance(from, to, transferred);
    }

    /// @dev Checks all compliance modules.
    function _checkCompliance(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual returns (ebool compliant) {
        address[] memory modules = _complianceModules.values();
        uint256 modulesLength = modules.length;
        compliant = FHE.asEbool(true);
        for (uint256 i = 0; i < modulesLength; i++) {
            if (FHE.isInitialized(encryptedAmount)) FHE.allowTransient(encryptedAmount, modules[i]);
            compliant = FHE.and(
                compliant,
                IComplianceModuleConfidential(modules[i]).isCompliantTransfer(from, to, encryptedAmount)
            );
        }
    }

    /// @dev Runs the post-transfer hooks for all compliance modules. This runs after all transfers (including force transfers).
    function _postTransferCompliance(address from, address to, euint64 encryptedAmount) internal virtual {
        address[] memory modules = _complianceModules.values();
        uint256 modulesLength = modules.length;
        for (uint256 i = 0; i < modulesLength; i++) {
            FHE.allowTransient(encryptedAmount, modules[i]);
            IComplianceModuleConfidential(modules[i]).postTransfer(from, to, encryptedAmount);
        }
    }

    /// @dev See {HandleAccessManager-_validateHandleAllowance}. Allow compliance modules to access any handle.
    function _validateHandleAllowance(bytes32) internal view override returns (bool) {
        return _complianceModules.contains(msg.sender);
    }
}
