// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC7984} from "./IERC7984.sol";

/// @dev Interface for confidential RWA contracts.
interface IERC7984Rwa is IERC7984, IERC165 {
    /// @dev Returns true if the contract is paused, false otherwise.
    function paused() external view returns (bool);
    /// @dev Returns whether an account is allowed to interact with the token.
    function isUserAllowed(address account) external view returns (bool);
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
