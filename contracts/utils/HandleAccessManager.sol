// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Impl} from "@fhevm/solidity/lib/Impl.sol";

abstract contract ACLAllowance {
    /**
     * @dev Get ACL allowance for the given handle `handle`. Allowance will be given to the
     * account `account` with the given persistence flag.
     *
     * NOTE: This function call is gated by the message sender and validated by the
     * {_validateACLAllowance} function.
     */
    function getACLAllowance(bytes32 handle, address account, bool persistent) public {
        _validateACLAllowance(handle);
        if (persistent) {
            Impl.allow(handle, account);
        } else {
            Impl.allowTransient(handle, account);
        }
    }

    /**
     * @dev Unimplemented function that must revert if the message sender is not allowed to call
     * {getACLAllowance} for the given handle.
     */
    function _validateACLAllowance(bytes32 handle) internal view virtual;
}
