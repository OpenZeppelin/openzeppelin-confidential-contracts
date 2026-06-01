// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.5.0-rc.0) (interfaces/IERC7984HookModule.sol)

pragma solidity ^0.8.24;

import {euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

/// @dev Interface for an ERC-7984 hook module.
interface IERC7984HookModule is IERC165 {
    /// @dev Optionally emitted by a module to indicate the result of its validation (pre-transfer) hook.
    event ERC7984HookModuleResult(
        address indexed token,
        address indexed from,
        address indexed to,
        euint64 encryptedAmount,
        ebool result,
        bytes32 context
    );

    /**
     * @dev Hook that runs before a transfer. Should not mutate token state. Module is already
     * granted transient access to `encryptedAmount`.
     */
    function preTransfer(address from, address to, euint64 encryptedAmount) external returns (ebool);

    /// @dev Performs operation after transfer.
    function postTransfer(address from, address to, euint64 encryptedAmount) external;

    /// @dev Performs operations after installation.
    function onInstall(bytes calldata initData) external;
}
