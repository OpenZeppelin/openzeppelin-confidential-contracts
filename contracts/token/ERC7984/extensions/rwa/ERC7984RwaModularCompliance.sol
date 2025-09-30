// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC7984RwaModularCompliance, IERC7984RwaComplianceModule} from "../../../../interfaces/IERC7984Rwa.sol";
import {HandleAccessManager} from "../../../../utils/HandleAccessManager.sol";
import {ERC7984Rwa} from "../ERC7984Rwa.sol";

/**
 * @dev Extension of {ERC7984Rwa} that supports compliance modules for confidential Real World Assets (RWAs).
 * Inspired by ERC-7579 modules.
 */
abstract contract ERC7984RwaModularCompliance is ERC7984Rwa, IERC7984RwaModularCompliance, HandleAccessManager {
    using EnumerableSet for *;

    EnumerableSet.AddressSet private _alwaysOnModules;
    EnumerableSet.AddressSet private _transferOnlyModules;

    /// @dev Emitted when a module is installed.
    event ModuleInstalled(ComplianceModuleType moduleType, address module);
    /// @dev Emitted when a module is uninstalled.
    event ModuleUninstalled(ComplianceModuleType moduleType, address module);

    /// @dev The module type is not supported.
    error ERC7984RwaUnsupportedModuleType(ComplianceModuleType moduleType);
    /// @dev The address is not a transfer compliance module.
    error ERC7984RwaNotTransferComplianceModule(address module);
    /// @dev The module is already installed.
    error ERC7984RwaAlreadyInstalledModule(ComplianceModuleType moduleType, address module);
    /// @dev The module is already uninstalled.
    error ERC7984RwaAlreadyUninstalledModule(ComplianceModuleType moduleType, address module);
    /// @dev The sender is not a compliance module.
    error SenderNotComplianceModule(address account);

    /**
     * @dev Check if a certain module typeId is supported.
     *
     * Supported module types:
     *
     * * Transfer compliance module
     * * Force transfer compliance module
     */
    function supportsModule(ComplianceModuleType moduleType) public view virtual returns (bool) {
        return moduleType == ComplianceModuleType.AlwaysOn || moduleType == ComplianceModuleType.TransferOnly;
    }

    /// @inheritdoc IERC7984RwaModularCompliance
    function isModuleInstalled(ComplianceModuleType moduleType, address module) public view virtual returns (bool) {
        return _isModuleInstalled(moduleType, module);
    }

    /**
     * @inheritdoc IERC7984RwaModularCompliance
     * @dev Consider gas footprint of the module before adding it since all modules will perform
     * all steps (pre-check, compliance check, post-hook) in a single transaction.
     */
    function installModule(ComplianceModuleType moduleType, address module) public virtual onlyAdmin {
        _installModule(moduleType, module);
    }

    /// @inheritdoc IERC7984RwaModularCompliance
    function uninstallModule(ComplianceModuleType moduleType, address module) public virtual onlyAdmin {
        _uninstallModule(moduleType, module);
    }

    /// @dev Checks if a compliance module is installed.
    function _isModuleInstalled(
        ComplianceModuleType moduleType,
        address module
    ) internal view virtual returns (bool installed) {
        if (moduleType == ComplianceModuleType.AlwaysOn) return _alwaysOnModules.contains(module);
        if (moduleType == ComplianceModuleType.TransferOnly) return _transferOnlyModules.contains(module);
    }

    /// @dev Internal function which installs a transfer compliance module.
    function _installModule(ComplianceModuleType moduleType, address module) internal virtual {
        require(supportsModule(moduleType), ERC7984RwaUnsupportedModuleType(moduleType));
        (bool success, bytes memory returnData) = module.staticcall(
            abi.encodePacked(IERC7984RwaComplianceModule.isModule.selector)
        );
        require(
            success && bytes4(returnData) == IERC7984RwaComplianceModule.isModule.selector,
            ERC7984RwaNotTransferComplianceModule(module)
        );

        if (moduleType == ComplianceModuleType.AlwaysOn) {
            require(_alwaysOnModules.add(module), ERC7984RwaAlreadyInstalledModule(moduleType, module));
        } else if (moduleType == ComplianceModuleType.TransferOnly) {
            require(_transferOnlyModules.add(module), ERC7984RwaAlreadyInstalledModule(moduleType, module));
        }
        emit ModuleInstalled(moduleType, module);
    }

    /// @dev Internal function which uninstalls a transfer compliance module.
    function _uninstallModule(ComplianceModuleType moduleType, address module) internal virtual {
        require(supportsModule(moduleType), ERC7984RwaUnsupportedModuleType(moduleType));
        if (moduleType == ComplianceModuleType.AlwaysOn) {
            require(_alwaysOnModules.remove(module), ERC7984RwaAlreadyUninstalledModule(moduleType, module));
        } else if (moduleType == ComplianceModuleType.TransferOnly) {
            require(_transferOnlyModules.remove(module), ERC7984RwaAlreadyUninstalledModule(moduleType, module));
        }
        emit ModuleUninstalled(moduleType, module);
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
        transferred = super._update(
            from,
            to,
            FHE.select(
                FHE.and(
                    _checkAlwaysBefore(from, to, encryptedAmount),
                    _checkOnlyBeforeTransfer(from, to, encryptedAmount)
                ),
                encryptedAmount,
                FHE.asEuint64(0)
            )
        );
        _runAlwaysAfter(from, to, transferred);
        _runOnlyAfterTransfer(from, to, transferred);
    }

    /**
     * @dev Forces the update of confidential balances. It transfers zero if it does not
     * follow force transfer compliance. Runs hooks after the force transfer.
     */
    function _forceUpdate(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual override returns (euint64 transferred) {
        transferred = super._update(
            from,
            to,
            FHE.select(_checkAlwaysBefore(from, to, encryptedAmount), encryptedAmount, FHE.asEuint64(0))
        );
        _runAlwaysAfter(from, to, transferred);
    }

    /// @dev Checks always-on compliance.
    function _checkAlwaysBefore(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual returns (ebool compliant) {
        if (!FHE.isInitialized(encryptedAmount)) {
            return FHE.asEbool(true);
        }
        address[] memory modules = _alwaysOnModules.values();
        uint256 modulesLength = modules.length;
        compliant = FHE.asEbool(true);
        for (uint256 i = 0; i < modulesLength; i++) {
            compliant = FHE.and(
                compliant,
                IERC7984RwaComplianceModule(modules[i]).isCompliantTransfer(from, to, encryptedAmount)
            );
        }
    }

    /// @dev Checks transfer-only compliance.
    function _checkOnlyBeforeTransfer(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual returns (ebool compliant) {
        if (!FHE.isInitialized(encryptedAmount)) {
            return FHE.asEbool(true);
        }
        address[] memory modules = _transferOnlyModules.values();
        uint256 modulesLength = modules.length;
        compliant = FHE.asEbool(true);
        for (uint256 i = 0; i < modulesLength; i++) {
            compliant = FHE.and(
                compliant,
                IERC7984RwaComplianceModule(modules[i]).isCompliantTransfer(from, to, encryptedAmount)
            );
        }
    }

    /// @dev Runs always after.
    function _runAlwaysAfter(address from, address to, euint64 encryptedAmount) internal virtual {
        address[] memory modules = _alwaysOnModules.values();
        uint256 modulesLength = modules.length;
        for (uint256 i = 0; i < modulesLength; i++) {
            IERC7984RwaComplianceModule(modules[i]).postTransfer(from, to, encryptedAmount);
        }
    }

    /// @dev Runs only after transfer.
    function _runOnlyAfterTransfer(address from, address to, euint64 encryptedAmount) internal virtual {
        address[] memory modules = _transferOnlyModules.values();
        uint256 modulesLength = modules.length;
        for (uint256 i = 0; i < modulesLength; i++) {
            IERC7984RwaComplianceModule(modules[i]).postTransfer(from, to, encryptedAmount);
        }
    }

    /// @dev Allow modules to get access to token handles over {HandleAccessManager-getHandleAllowance}.
    function _validateHandleAllowance(bytes32) internal view override {
        require(
            _alwaysOnModules.contains(msg.sender) || _transferOnlyModules.contains(msg.sender),
            SenderNotComplianceModule(msg.sender)
        );
    }
}
