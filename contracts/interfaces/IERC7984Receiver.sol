// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.2.0) (interfaces/IConfidentialFungibleTokenReceiver.sol)
pragma solidity ^0.8.24;

import {ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";

/// @dev Interface for contracts that can receive ERC7984 transfers with a callback.
interface IERC7984Receiver {
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
