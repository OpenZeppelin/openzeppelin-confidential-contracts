// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ebool, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC7984} from "./IERC7984.sol";
import {IERC7984Restricted} from "./IERC7984Restricted.sol";

/// @dev Base interface for confidential RWA contracts.
interface IERC7984RwaBase {
    /// @dev Emitted when the contract is paused.
    event Paused(address account);
    /// @dev Emitted when the contract is unpaused.
    event Unpaused(address account);

    /// @dev The caller account is not authorized to perform an operation.
    error OwnableUnauthorizedAccount(address account);
    /// @dev The owner is not a valid owner account. (eg. `address(0)`)
    error OwnableInvalidOwner(address owner);
    /// @dev The operation failed because the contract is paused.
    error EnforcedPause();

    /// @dev Returns true if has admin role, false otherwise.
    function isAdmin(address account) external view returns (bool);
    /// @dev Returns true if agent, false otherwise.
    function isAgent(address account) external view returns (bool);
    /// @dev Returns true if admin or agent, false otherwise.
    function isAdminOrAgent(address account) external view returns (bool);
    /// @dev Returns true if the contract is paused, and false otherwise.
    function paused() external view returns (bool);
    /// @dev Pauses contract.
    function pause() external;
    /// @dev Unpauses contract.
    function unpause() external;
    /// @dev Returns the restriction of a user account.
    function getRestriction(address account) external view returns (IERC7984Restricted.Restriction);
    /// @dev Blocks a user account.
    function blockUser(address account) external;
    /// @dev Unblocks a user account.
    function unblockUser(address account) external;
    /// @dev Returns whether an account is allowed to interact with the token.
    function isUserAllowed(address account) external view returns (bool);
    /// @dev Returns the confidential frozen balance of an account.
    function confidentialFrozen(address account) external view returns (euint64);
    /// @dev Returns the available (unfrozen) balance of an account. Up to {confidentialBalanceOf}.
    function confidentialAvailable(address account) external returns (euint64);
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
    /// @dev Receives and executes a batch of function calls on this contract.
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}

/// @dev Full interface for confidential RWA contracts.
interface IERC7984Rwa is IERC7984, IERC7984RwaBase, IERC165, IAccessControl {}

/// @dev Interface for confidential RWA with modular compliance.
interface IERC7984RwaModularCompliance {
    enum ComplianceModuleType {
        ALWAYS_ON,
        TRANSFER_ONLY
    }

    /// @dev Installs a transfer compliance module.
    function installModule(ComplianceModuleType moduleType, address module) external;
    /// @dev Uninstalls a transfer compliance module.
    function uninstallModule(ComplianceModuleType moduleType, address module) external;
    /// @dev Checks if a compliance module is installed.
    function isModuleInstalled(ComplianceModuleType moduleType, address module) external view returns (bool);
}

/// @dev Interface for confidential RWA transfer compliance module.
interface IERC7984RwaComplianceModule {
    /// @dev Returns magic number if it is a module.
    function isModule() external returns (bytes4);
    /// @dev Checks if a transfer is compliant. Should be non-mutating.
    function isCompliantTransfer(address from, address to, euint64 encryptedAmount) external returns (ebool);
    /// @dev Performs operation after transfer.
    function postTransfer(address from, address to, euint64 encryptedAmount) external;
}
