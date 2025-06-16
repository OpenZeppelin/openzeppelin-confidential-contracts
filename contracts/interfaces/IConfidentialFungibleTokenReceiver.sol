// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ebool, euint64} from "fhevm/lib/TFHE.sol";

/// @dev Interface for contracts that can receive confidential token transfers with a callback.
interface IConfidentialFungibleTokenReceiver {
    /**
     * @dev Called upon receiving a confidential token transfer. Returns an encrypted boolean indicating success
     * of the callback. If false is returned, the transfer must be reversed.
     */
    function onConfidentialTransferReceived(
        address operator,
        address from,
        euint64 amount,
        bytes calldata data
    ) external returns (ebool);
}
