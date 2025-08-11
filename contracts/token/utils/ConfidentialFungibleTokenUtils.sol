// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";

import {IConfidentialFungibleTokenReceiver} from "../../interfaces/IConfidentialFungibleTokenReceiver.sol";
import {ConfidentialFungibleToken} from "../ConfidentialFungibleToken.sol";

/// @dev Library that provides common {ConfidentialFungibleToken} utility functions.
library ConfidentialFungibleTokenUtils {
    /**
     * @dev Performs a transfer callback to the recipient of the transfer `to`. Should be invoked
     * after all transfers "withCallback" on a {ConfidentialFungibleToken}.
     *
     * The transfer callback is not invoked on the recipient if the recipient has no code (i.e. is an EOA). If the
     * recipient has non-zero code, it must implement
     * {IConfidentialFungibleTokenReceiver-onConfidentialTransferReceived} and return an `ebool` indicating
     * whether the transfer was accepted or not. If the `ebool` is `false`, the transfer will be reversed.
     */
    function checkOnTransferReceived(
        address operator,
        address from,
        address to,
        euint64 amount,
        bytes calldata data
    ) internal returns (ebool) {
        if (to.code.length > 0) {
            try
                IConfidentialFungibleTokenReceiver(to).onConfidentialTransferReceived(operator, from, amount, data)
            returns (ebool retval) {
                return retval;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert ConfidentialFungibleToken.ConfidentialFungibleTokenInvalidReceiver(to);
                } else {
                    assembly ("memory-safe") {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return FHE.asEbool(true);
        }
    }
}
