// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IComplianceModuleConfidential} from "./../../interfaces/IComplianceModuleConfidential.sol";
import {IERC7984Rwa} from "./../../interfaces/IERC7984Rwa.sol";
import {HandleAccessManager} from "./../../utils/HandleAccessManager.sol";

/**
 * @dev A contract which allows to build a transfer compliance module for confidential Real World Assets (RWAs).
 */
abstract contract ComplianceModuleConfidential is IComplianceModuleConfidential, ERC165 {
    error UnauthorizedUseOfEncryptedAmount(euint64 encryptedAmount, address sender);

    /// @dev Thrown when the sender is not authorized to call the given function.
    error NotAuthorized(address account);

    /// @dev Thrown when the sender is not an admin of the token.
    modifier onlyTokenAdmin(address token) {
        require(IERC7984Rwa(token).isAdmin(msg.sender), NotAuthorized(msg.sender));
        _;
    }

    /// @dev Thrown when the sender is not an agent of the token.
    modifier onlyTokenAgent(address token) {
        require(IERC7984Rwa(token).isAgent(msg.sender), NotAuthorized(msg.sender));
        _;
    }

    /// @inheritdoc IComplianceModuleConfidential
    function isCompliantTransfer(address from, address to, euint64 encryptedAmount) public virtual returns (ebool) {
        ebool compliant = _isCompliantTransfer(msg.sender, from, to, encryptedAmount);
        FHE.allowTransient(compliant, msg.sender);
        return compliant;
    }

    /// @inheritdoc IComplianceModuleConfidential
    function postTransfer(address from, address to, euint64 encryptedAmount) public virtual {
        _postTransfer(msg.sender, from, to, encryptedAmount);
    }

    /// @inheritdoc IComplianceModuleConfidential
    function onInstall(bytes calldata initData) public virtual {}

    /// @inheritdoc IComplianceModuleConfidential
    function onUninstall(bytes calldata deinitData) public virtual {}

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IComplianceModuleConfidential).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Internal function which checks if a transfer is compliant. Transient access is already granted to the module
     * for `encryptedAmount`. If additional handle access is needed from the token, call {_getTokenHandleAllowance}.
     */
    function _isCompliantTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual returns (ebool);

    /**
     * @dev Internal function which performs operations after transfers. Transient access is already granted to the module
     * for `encryptedAmount`. If additional handle access is needed from the token, call {_getTokenHandleAllowance}.
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
