// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";

/// @dev Interface for confidential RWA transfer compliance module.
interface IComplianceModuleConfidential {
    /// @dev Returns magic number if it is a module.
    function isModule() external returns (bytes4);

    /// @dev Checks if a transfer is compliant. Should be non-mutating.
    function isCompliantTransfer(address from, address to, euint64 encryptedAmount) external returns (ebool);

    /// @dev Performs operation after transfer.
    function postTransfer(address from, address to, euint64 encryptedAmount) external;

    /// @dev Performs operation after installation.
    function onInstall(bytes calldata initData) external;

    /// @dev Performs operation after uninstallation.
    function onUninstall(bytes calldata deinitData) external;
}
