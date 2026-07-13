// SPDX-License-Identifier: MIT

pragma solidity >=0.8.24;

import {IERC7984} from "./IERC7984.sol";

/// @dev Interface for an ERC-7984 token that supports hook modules.
interface IERC7984Hooked is IERC7984 {
    /// @dev Emitted when a module is installed.
    event ERC7984HookedModuleInstalled(address module);

    /// @dev Emitted when a module is uninstalled.
    event ERC7984HookedModuleUninstalled(address module);

    /// @dev Checks if a module is installed.
    function isModuleInstalled(address module) external view returns (bool);

    /**
     * @dev Installs a hook module.
     *
     * Consider gas footprint of the module before adding it since all modules will perform
     * both steps (pre-hook, post-hook) on all transfers.
     */
    function installModule(address module, bytes memory initData) external;

    /// @dev Uninstalls a hook module.
    function uninstallModule(address module) external;

    /**
     * @dev Returns whether `account` is a hook manager, authorized to install, uninstall, and configure
     * hook modules on this token.
     *
     * Hook modules query this function to gate their configuration entry points. The token is the
     * source of truth for who may manage its hooks.
     */
    function isHookManager(address account) external view returns (bool);
}
