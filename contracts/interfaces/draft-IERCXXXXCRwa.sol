// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC7984} from "./IERC7984.sol";

/// @dev Interface for confidential RWA contracts.
interface IERCXXXXCRwa is IERC7984, IERC165, IAccessControl {
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
    /// @dev The operation failed because the contract is not paused.
    error ExpectedPause();

    /// @dev Returns true if the contract is paused, and false otherwise.
    function paused() external view returns (bool);
    /// @dev Pauses contract.
    function pause() external;
    /// @dev Unpauses contract.
    function unpause() external;
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
    /// @dev Receives and executes a batch of function calls on this contract.
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
    /// @dev Mints confidential amount of tokens to account with proof.
    function mint(address to, externalEuint64 encryptedAmount, bytes calldata inputProof) external returns (euint64);
    /// @dev Mints confidential amount of tokens to account.
    function mint(address to, euint64 encryptedAmount) external;
    /// @dev Burns confidential amount of tokens from account with proof.
    function burn(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external returns (euint64);
    /// @dev Burns confidential amount of tokens from account.
    function burn(address account, euint64 encryptedAmount) external returns (euint64);
    /// @dev Forces transfer of confidential amount of tokens from account to account with proof by skipping compliance checks.
    function forceTransfer(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external returns (euint64);
    /// @dev Forces transfer of confidential amount of tokens from account to account by skipping compliance checks.
    function forceTransfer(address from, address to, euint64 encryptedAmount) external returns (euint64);
}

/// @dev Interface for confidential RWA compliance.
interface IERCXXXXCRWACompliance {
    /// @dev Checks if a transfer follows token compliance.
    function isCompliantTransfer(address from, address to, euint64 encryptedAmount) external returns (bool);
}
