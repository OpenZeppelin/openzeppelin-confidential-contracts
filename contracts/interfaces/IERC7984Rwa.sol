// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.3.0) (interfaces/IERC7984Rwa.sol)
pragma solidity ^0.8.24;

import {ebool, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984} from "./IERC7984.sol";

/// @dev Interface for confidential RWA contracts.
interface IERC7984Rwa is IERC7984 {
    /// @dev Returns true if the contract is paused, false otherwise.
    function paused() external view returns (bool);

    /// @dev Returns true if has admin role, false otherwise.
    function isAdmin(address account) external view returns (bool);

    /// @dev Returns true if agent, false otherwise.
    function isAgent(address account) external view returns (bool);

    /// @dev Returns true if admin or agent, false otherwise.
    function isAdminOrAgent(address account) external view returns (bool);

    /// @dev Returns whether an account is allowed to interact with the token.
    function canTransact(address account) external view returns (bool);

    /// @dev Returns the confidential frozen balance of an account.
    function confidentialFrozen(address account) external view returns (euint64);

    /// @dev Returns the confidential available (unfrozen) balance of an account. Up to {IERC7984-confidentialBalanceOf}.
    function confidentialAvailable(address account) external returns (euint64);

    /// @dev Pauses contract.
    function pause() external;

    /// @dev Unpauses contract.
    function unpause() external;

    /// @dev Blocks a user account.
    function blockUser(address account) external;

    /// @dev Unblocks a user account.
    function unblockUser(address account) external;

    /// @dev Sets confidential amount of token for an account as frozen with proof.
    function setConfidentialFrozen(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external;

    /// @dev Sets confidential amount of token for an account as frozen.
    function setConfidentialFrozen(address account, euint64 encryptedAmount) external;

    /// @dev Mints confidential amount of tokens to account with proof.
    function confidentialMint(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external returns (euint64);

    /// @dev Mints confidential amount of tokens to account.
    function confidentialMint(address to, euint64 encryptedAmount) external returns (euint64);

    /// @dev Burns confidential amount of tokens from account with proof.
    function confidentialBurn(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external returns (euint64);

    /// @dev Burns confidential amount of tokens from account.
    function confidentialBurn(address account, euint64 encryptedAmount) external returns (euint64);

    /// @dev Forces transfer of confidential amount of tokens from account to account with proof by skipping compliance checks.
    function forceConfidentialTransferFrom(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external returns (euint64);

    /// @dev Forces transfer of confidential amount of tokens from account to account by skipping compliance checks.
    function forceConfidentialTransferFrom(
        address from,
        address to,
        euint64 encryptedAmount
    ) external returns (euint64);
}

/// @dev Interface for confidential RWA with modular compliance.
interface IERC7984RwaModularCompliance {
    enum ComplianceModuleType {
        Standard,
        ForceTransfer
    }

    /// @dev Checks if a compliance module is installed.
    function isModuleInstalled(ComplianceModuleType moduleType, address module) external view returns (bool);

    /// @dev Installs a transfer compliance module.
    function installModule(ComplianceModuleType moduleType, address module, bytes calldata initData) external;

    /// @dev Uninstalls a transfer compliance module.
    function uninstallModule(ComplianceModuleType moduleType, address module, bytes calldata deinitData) external;
}

/// @dev Interface for confidential RWA transfer compliance module.
interface IERC7984RwaComplianceModule {
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
