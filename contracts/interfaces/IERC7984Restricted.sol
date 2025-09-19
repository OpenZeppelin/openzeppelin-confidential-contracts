// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @dev Interface for contracts that implements user account transfer restrictions.
interface IERC7984Restricted {
    enum Restriction {
        DEFAULT, // User has no explicit restriction
        BLOCKED, // User is explicitly blocked
        ALLOWED // User is explicitly allowed
    }

    /// @dev Emitted when a user account's restriction is updated.
    event UserRestrictionUpdated(address indexed account, Restriction restriction);

    /// @dev The operation failed because the user account is restricted.
    error UserRestricted(address account);

    /// @dev Returns the restriction of a user account.
    function getRestriction(address account) external view returns (Restriction);
    /// @dev Returns whether a user account is allowed to interact with the token.
    function isUserAllowed(address account) external view returns (bool);
}
