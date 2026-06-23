// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.3.0) (token/ERC7984/utils/ERC7984Utils.sol)
pragma solidity ^0.8.26;

import {ebool, euint64} from "encrypted-types/EncryptedTypes.sol";

import {IERC7984Receiver} from "../../../interfaces/IERC7984Receiver.sol";
import {ERC7984} from "../ERC7984.sol";

/// @dev Library that provides common {ERC7984} utility functions.
library ERC7984Utils {
    /**
     * @dev Performs a transfer callback to the recipient of the transfer `to`. Should be invoked
     * after all transfers "withCallback" on a {ERC7984}, only when the recipient `to` has non-zero
     * code (i.e. is a contract); the caller is responsible for short-circuiting EOAs as accepted.
     *
     * The recipient must implement {IERC7984Receiver-onConfidentialTransferReceived} and return an
     * `ebool` indicating whether the transfer was accepted or not. If the `ebool` is `false`, the
     * transfer function should try to refund the `from` address.
     */
    function checkOnTransferReceived(
        address operator,
        address from,
        address to,
        euint64 amount,
        bytes calldata data
    ) internal returns (ebool) {
        try IERC7984Receiver(to).onConfidentialTransferReceived(operator, from, amount, data) returns (ebool retval) {
            return retval;
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                revert ERC7984.ERC7984InvalidReceiver(to);
            } else {
                assembly ("memory-safe") {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }
}
