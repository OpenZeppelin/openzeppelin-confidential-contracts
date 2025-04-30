// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TFHE, ebool, euint64 } from "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { IConfidentialFungibleTokenReceiver } from "../interfaces/IConfidentialFungibleTokenReceiver.sol";

contract ConfidentialFungibleTokenReceiverMock is IConfidentialFungibleTokenReceiver, SepoliaZamaFHEVMConfig {
    using TFHE for *;

    event ConfidentialTransferCallback(bool success);

    error InvalidInput(uint8 input);

    /// Data should contain a success boolean (plaintext). Revert if not.
    function onConfidentialTransferReceived(address, address, euint64, bytes calldata data) external returns (ebool) {
        uint8 input = abi.decode(data, (uint8));

        if (input > 1) revert InvalidInput(input);

        bool success = input == 1;
        emit ConfidentialTransferCallback(success);

        ebool returnVal = TFHE.asEbool(success);
        returnVal.allowTransient(msg.sender);

        return returnVal;
    }
}
