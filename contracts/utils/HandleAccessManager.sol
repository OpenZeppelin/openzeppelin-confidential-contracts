// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {Impl} from "@fhevm/solidity/lib/Impl.sol";

abstract contract HandleAccessManager {
    //TODO: Use storage namespace
    mapping(bytes4 handleFunctionSelector => bytes4) private _accessFunctionSelectors;

    error UnallowedHandleAccess(bytes32 handle, address account);

    modifier onlySenderAccess(bytes32 handle, address account) {
        require(msg.sender == account, UnallowedHandleAccess(handle, account));
        _;
    }

    /// @dev Support handle access functions discoverability
    function getHandleAccessFunctionSelector(bytes4 handleFunctionSelector) public view virtual returns (bytes4) {
        return _accessFunctionSelectors[handleFunctionSelector];
    }

    function setHandleAccessFunctionSelector(bytes4 handleSelector, bytes4 accessSelector) public virtual {
        _accessFunctionSelectors[handleSelector] = accessSelector;
    }

    //TODO: Add all other handle types (euint8, ...)
    function _getHandleAllowance(euint64 handle, address account) internal virtual {
        _getHandleAllowance(euint64.unwrap(handle), account);
    }

    function _getHandleAllowance(bytes32 handle, address account) internal virtual {
        _validateHandleAllowance(handle, account);
        Impl.allow(handle, account);
    }

    /**
     * @dev Get handle access for the given handle `handle`. Access will be given to the
     * account `account` with the given persistence flag.
     *
     * NOTE: This function call is gated by `msg.sender` and validated by the
     * {_validateHandleAllowance} function.
     */
    //TODO: Rename to allowHandleAccess
    //TODO: Set internal
    function getHandleAllowance(bytes32 handle, address account, bool persistent) public virtual {
        _validateHandleAllowance(handle, account);
        if (persistent) {
            Impl.allow(handle, account);
        } else {
            Impl.allowTransient(handle, account);
        }
    }

    /**
     * @dev Unimplemented function that must revert if the message sender is not allowed to call
     * {getHandleAllowance} for the given handle.
     */
    //TODO: Rename to _validateHandleAccess
    function _validateHandleAllowance(bytes32 handle, address account) internal view virtual;
}
