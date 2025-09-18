// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984Rwa, IERC7984RwaComplianceModule} from "../../../../interfaces/IERC7984Rwa.sol";
import {HandleAccessManager} from "../../../../utils/HandleAccessManager.sol";

/**
 * @dev A contract which allows to build a transfer compliance module for confidential Real World Assets (RWAs).
 */
abstract contract ERC7984RwaComplianceModule is IERC7984RwaComplianceModule, HandleAccessManager {
    address internal immutable _token;

    /// @dev The sender is not the token.
    error SenderNotToken(address account);
    /// @dev The sender is not the token admin.
    error SenderNotTokenAdmin(address account);
    /// @dev The sender is not a token agent.
    error SenderNotTokenAgent(address account);
    /// @dev The sender is not the token admin or a token agent.
    error SenderNotTokenAdminOrTokenAgent(address account);

    /// @dev Throws if called by any account other than the token.
    modifier onlyToken() {
        require(msg.sender == _token, SenderNotToken(msg.sender));
        _;
    }

    /// @dev Throws if called by any account other than the token admin.
    modifier onlyTokenAdmin() {
        require(IERC7984Rwa(_token).isAdmin(msg.sender), SenderNotTokenAdmin(msg.sender));
        _;
    }

    /// @dev Throws if called by any account other than a token agent.
    modifier onlyTokenAgent() {
        require(IERC7984Rwa(_token).isAgent(msg.sender), SenderNotTokenAgent(msg.sender));
        _;
    }

    /// @dev Throws if called by any account other than the token admin or a token agent.
    modifier onlyTokenAdminOrTokenAgent() {
        require(IERC7984Rwa(_token).isAdminOrAgent(msg.sender), SenderNotTokenAdminOrTokenAgent(msg.sender));
        _;
    }

    constructor(address token) {
        _token = token;
    }

    /// @inheritdoc IERC7984RwaComplianceModule
    function isModule() public pure override returns (bytes4) {
        return this.isModule.selector;
    }

    /// @inheritdoc IERC7984RwaComplianceModule
    function isCompliantTransfer(
        address from,
        address to,
        euint64 encryptedAmount
    ) public virtual onlyToken returns (ebool compliant) {
        FHE.allow(compliant = _isCompliantTransfer(from, to, encryptedAmount), msg.sender);
    }

    /// @inheritdoc IERC7984RwaComplianceModule
    function postTransfer(address from, address to, euint64 encryptedAmount) public virtual onlyToken {
        _postTransfer(from, to, encryptedAmount);
    }

    /// @dev Internal function which checks if a transfer is compliant.
    function _isCompliantTransfer(
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal virtual returns (ebool);

    /// @dev Internal function which Performs operation after transfer.
    function _postTransfer(address /*from*/, address /*to*/, euint64 /*encryptedAmount*/) internal virtual {
        // default to no-op
    }

    /// @dev Allow modules to get access to token handles during transaction.
    function _getTokenHandleAllowance(euint64 handle) internal virtual {
        _getTokenHandleAllowance(handle, false);
    }

    /// @dev Allow modules to get access to token handles.
    function _getTokenHandleAllowance(euint64 handle, bool persistent) internal virtual {
        if (FHE.isInitialized(handle)) {
            HandleAccessManager(_token).getHandleAllowance(euint64.unwrap(handle), address(this), persistent);
        }
    }

    function _validateHandleAllowance(bytes32 handle) internal view override onlyTokenAdminOrTokenAgent {}
}
