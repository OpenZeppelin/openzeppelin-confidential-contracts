// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984Rwa, IERC7984RwaComplianceModule} from "../../../../interfaces/IERC7984Rwa.sol";
import {HandleAccessManager} from "../../../../utils/HandleAccessManager.sol";

/**
 * @dev A contract which allows to build a transfer compliance module for confidential Real World Assets (RWAs).
 */
abstract contract ERC7984RwaComplianceModule is IERC7984RwaComplianceModule {
    /// @dev Thrown when the sender is not authorized to call the given function.
    error NotAuthorized(address account);

    modifier onlyTokenAgent(address token) {
        require(IERC7984Rwa(token).isAgent(msg.sender), NotAuthorized(msg.sender));
        _;
    }

    /// @inheritdoc IERC7984RwaComplianceModule
    function isModule() public pure override returns (bytes4) {
        return this.isModule.selector;
    }

    /// @inheritdoc IERC7984RwaComplianceModule
    function isCompliantTransfer(address from, address to, euint64 encryptedAmount) public virtual returns (ebool) {
        ebool compliant = _isCompliantTransfer(msg.sender, from, to, encryptedAmount);
        FHE.allowTransient(compliant, msg.sender);
        return compliant;
    }

    /// @inheritdoc IERC7984RwaComplianceModule
    function postTransfer(address from, address to, euint64 encryptedAmount) public virtual {
        _postTransfer(msg.sender, from, to, encryptedAmount);
    }

    /// @dev Internal function which checks if a transfer is compliant.
    function _isCompliantTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual returns (ebool);

    /// @dev Internal function which performs operation after transfer.
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
