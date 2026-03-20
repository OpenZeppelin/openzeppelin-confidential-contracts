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
    /// @dev The caller `user` does not have access to the encrypted amount `amount`.
    error ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(euint64 amount, address user);

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
    function onInstall(bytes calldata initData) public virtual {}

    /// @inheritdoc IERC7984HookModule
    function onUninstall(bytes calldata deinitData) public virtual {}

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC7984HookModule).interfaceId || super.supportsInterface(interfaceId);
    }

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
}
