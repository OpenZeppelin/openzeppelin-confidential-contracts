// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC7984HookModule} from "./../../../interfaces/IERC7984HookModule.sol";
import {HandleAccessManager} from "./../../../utils/HandleAccessManager.sol";

/**
 * @dev An abstract base contract for building ERC-7984 hook modules. Compatible with {ERC7984Hooked}.
 */
abstract contract ERC7984HookModule is IERC7984HookModule, ERC165 {
    /// @dev The caller `account` is not authorized to perform the operation.
    error ERC7984HookModuleUnauthorizedAccount(address account);

    /// @dev The caller `user` does not have access to the encrypted amount `amount`.
    error ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(euint64 amount, address user);

    /// @dev The module is already installed for the given token.
    error ERC7984HookModuleAlreadyInstalled(address token);

    /// @dev The module is not installed for the given token.
    error ERC7984HookModuleNotInstalled(address token);

    /// @inheritdoc IERC7984HookModule
    function preTransfer(address from, address to, euint64 encryptedAmount) public virtual returns (ebool) {
        require(
            FHE.isAllowed(encryptedAmount, msg.sender),
            ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(encryptedAmount, msg.sender)
        );
        ebool compliant = _preTransfer(msg.sender, from, to, encryptedAmount);
        FHE.allowTransient(compliant, msg.sender);
        return compliant;
    }

    /// @inheritdoc IERC7984HookModule
    function postTransfer(address from, address to, euint64 encryptedAmount) public virtual {
        require(
            FHE.isAllowed(encryptedAmount, msg.sender),
            ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(encryptedAmount, msg.sender)
        );
        _postTransfer(msg.sender, from, to, encryptedAmount);
    }

    /// @inheritdoc IERC7984HookModule
    function onInstall(bytes calldata initData) public virtual {
        require(!_isModuleInstalled(msg.sender), ERC7984HookModuleAlreadyInstalled(msg.sender));

        _onInstall(msg.sender, initData);
    }

    /// @inheritdoc IERC7984HookModule
    function onUninstall(bytes calldata deinitData) public virtual {
        require(_isModuleInstalled(msg.sender), ERC7984HookModuleNotInstalled(msg.sender));

        _onUninstall(msg.sender, deinitData);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC7984HookModule).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Internal function which may be overridden by the derived contract to perform actions
     * when the module is installed.
     */
    function _onInstall(address token, bytes calldata initData) internal virtual {}

    /**
     * @dev Internal function which may be overridden by the derived contract to perform actions
     * when the module is uninstalled.
     */
    function _onUninstall(address token, bytes calldata deinitData) internal virtual {}

    /**
     * @dev Internal function which runs before a transfer. Transient access is already granted to the module
     * for `encryptedAmount`. If additional handle access is needed from the token, call {_getTokenHandleAllowance}.
     *
     * NOTE: ACL allowance on `encryptedAmount` is already checked for `msg.sender` in {preTransfer}.
     */
    function _preTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual returns (ebool);

    /**
     * @dev Internal function which performs operations after transfers. Transient access is already granted to the module
     * for `encryptedAmount`. If additional handle access is needed from the token, call {_getTokenHandleAllowance}.
     *
     * NOTE: ACL allowance on `encryptedAmount` is already checked for `msg.sender` in {postTransfer}.
     */
    function _postTransfer(
        address /*token*/,
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal virtual {
        // default to no-op
    }

    /**
     * @dev Check if the module is installed for the given token. This function must be implemented by the derived contract.
     *
     * NOTE: This function should use internal storage to check if the module is installed for the given token.
     * Do not use external storage like {ERC7984Hooked-isModuleInstalled}.
     */
    function _isModuleInstalled(address token) internal view virtual returns (bool);

    /// @dev Allow modules to get access to token handles during transaction.
    function _getTokenHandleAllowance(address token, euint64 handle) internal virtual {
        _getTokenHandleAllowance(token, handle, false);
    }

    /// @dev Allow modules to get access to token handles.
    function _getTokenHandleAllowance(address token, euint64 handle, bool persistent) internal virtual {
        if (FHE.isInitialized(handle)) {
            HandleAccessManager(token).getHandleAllowance(euint64.unwrap(handle), address(this), persistent);
        }
    }

    /**
     * @dev Get transient ACL allowance for the given handle from a contract that inherits {HandleAccessManager}.
     *
     * Additionally verifies that the token is authorized to access the handle.
     */
    function _accessHandle(address token, euint64 handle) internal {
        if (!FHE.isInitialized(handle)) return;
        require(FHE.isAllowed(handle, token), ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(handle, token));
        _getTokenHandleAllowance(token, handle, false);
    }
}
