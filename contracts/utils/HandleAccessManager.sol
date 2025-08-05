// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Impl} from "@fhevm/solidity/lib/Impl.sol";

abstract contract HandleAccessManager {
    /**
     * @dev Get handle access for the given handle `handle`. Access will be given to the
     * account `account` with the given persistence flag.
     *
     * NOTE: This function call is gated by `msg.sender` and validated by the
     * {_validateHandleAccess} function.
     */
    function getHandleAllowance(bytes32 handle, address account, bool persistent) public {
        _validateHandleAccess(handle);
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
    function _validateHandleAccess(bytes32 handle) internal view virtual;
}
