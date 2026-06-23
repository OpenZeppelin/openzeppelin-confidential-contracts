// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.5.0) (interfaces/IERC7984Hooked.sol)

pragma solidity >=0.8.24;

/// @dev Interface for an ERC-7984 token that supports hook modules and exposes module configuration authorization.
interface IERC7984Hooked {
    /**
     * @dev Returns whether `account` is authorized to configure hook modules installed on this token.
     *
     * Hook modules query this function to gate their configuration entry points. The token is the
     * source of truth for who may configure its modules.
     */
    function isAuthorizedConfigurator(address account) external view returns (bool);
}
