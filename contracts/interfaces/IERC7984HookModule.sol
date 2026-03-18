// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

/// @dev Interface for an ERC-7984 hook module.
interface IERC7984HookModule is IERC165 {
    /**
     * @dev Hook that runs before a transfer. Should be non-mutating. Transient access is already granted
     * to the module for `encryptedAmount`.
     */
    function preTransfer(address from, address to, euint64 encryptedAmount) external returns (ebool);

    /// @dev Performs operation after transfer.
    function postTransfer(address from, address to, euint64 encryptedAmount) external;

    /// @dev Performs operations after installation.
    function onInstall(bytes calldata initData) external;

    /// @dev Performs operations after uninstallation.
    function onUninstall(bytes calldata deinitData) external;
}
