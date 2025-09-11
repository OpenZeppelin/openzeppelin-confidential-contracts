// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7984, euint64} from "../ERC7984.sol";

/**
 * @dev Extension of {ERC7984} that implements user account transfer restrictions through the
 * {isUserAllowed} function. Inspired by
 * https://github.com/OpenZeppelin/openzeppelin-community-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Restricted.sol.
 *
 * By default, each account has no explicit restriction. The {isUserAllowed} function acts as
 * a blocklist. Developers can override {isUserAllowed} to check that `restriction == ALLOWED`
 * to implement an allowlist.
 */
abstract contract ERC7984Restricted is ERC7984 {
    enum Restriction {
        DEFAULT, // User has no explicit restriction
        BLOCKED, // User is explicitly blocked
        ALLOWED // User is explicitly allowed
    }

    mapping(address account => Restriction) private _restrictions;

    /// @dev Emitted when a user account's restriction is updated.
    event UserRestrictionUpdated(address indexed account, Restriction restriction);

    /// @dev The operation failed because the user account is restricted.
    error UserRestricted(address account);

    /// @dev Returns the restriction of a user account.
    function getRestriction(address account) public view virtual returns (Restriction) {
        return _restrictions[account];
    }

    /**
     * @dev Returns whether a user account is allowed to interact with the token.
     *
     * Default implementation only disallows explicitly BLOCKED accounts (i.e. a blocklist).
     *
     * To convert into an allowlist, override as:
     *
     * ```solidity
     * function isUserAllowed(address account) public view virtual override returns (bool) {
     *     return getRestriction(account) == Restriction.ALLOWED;
     * }
     * ```
     */
    function isUserAllowed(address account) public view virtual returns (bool) {
        return getRestriction(account) != Restriction.BLOCKED; // i.e. DEFAULT && ALLOWED
    }

    /**
     * @dev See {ERC7984-_update}. Enforces transfer restrictions (excluding minting and burning).
     *
     * Requirements:
     *
     * * `from` must be allowed to transfer tokens (see {isUserAllowed}).
     * * `to` must be allowed to receive tokens (see {isUserAllowed}).
     */
    function _update(address from, address to, euint64 value) internal virtual override returns (euint64) {
        if (from != address(0)) _checkRestriction(from); // Not minting
        if (to != address(0)) _checkRestriction(to); // Not burning
        return super._update(from, to, value);
    }

    /// @dev Updates the restriction of a user account.
    function _setRestriction(address account, Restriction restriction) internal virtual {
        if (getRestriction(account) != restriction) {
            _restrictions[account] = restriction;
            emit UserRestrictionUpdated(account, restriction);
        } // no-op if restriction is unchanged
    }

    /// @dev Convenience function to block a user account (set to BLOCKED).
    function _blockUser(address account) internal virtual {
        _setRestriction(account, Restriction.BLOCKED);
    }

    /// @dev Convenience function to allow a user account (set to ALLOWED).
    function _allowUser(address account) internal virtual {
        _setRestriction(account, Restriction.ALLOWED);
    }

    /// @dev Convenience function to reset a user account to default restriction.
    function _resetUser(address account) internal virtual {
        _setRestriction(account, Restriction.DEFAULT);
    }

    /// @dev Checks if a user account is restricted. Reverts with {ERC20Restricted} if so.
    function _checkRestriction(address account) internal view virtual {
        require(isUserAllowed(account), UserRestricted(account));
    }
}
