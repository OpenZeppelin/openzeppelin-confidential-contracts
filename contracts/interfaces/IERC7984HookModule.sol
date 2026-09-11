// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.5.0) (interfaces/IERC7984HookModule.sol)

pragma solidity >=0.8.24;

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
     *
     * `operator` is the address that initiated the transfer on the token. It is equal to `from` for
     * direct transfers, and differs from it when the transfer is initiated by an approved operator or
     * by the token itself (e.g. mints, burns and forced transfers).
     */
    function preTransfer(address operator, address from, address to, euint64 encryptedAmount) external returns (ebool);

    /// @dev Performs operation after transfer. See {preTransfer} for the meaning of `operator`.
    function postTransfer(address operator, address from, address to, euint64 encryptedAmount) external;

    /// @dev Performs operations after installation.
    function onInstall(bytes calldata initData) external;
}
