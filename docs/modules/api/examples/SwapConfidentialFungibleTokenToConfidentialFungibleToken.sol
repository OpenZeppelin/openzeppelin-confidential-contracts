// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TFHE, einput, euint64} from "fhevm/lib/TFHE.sol";
import {IConfidentialFungibleToken} from "@openzeppelin/confidential-contracts/interfaces/IConfidentialFungibleToken.sol";

contract SwapConfidentialFungibleTokenToConfidentialFungibleToken {
    function swapConfidentialForConfidential(
        IConfidentialFungibleToken fromToken,
        IConfidentialFungibleToken toToken,
        einput amountInput,
        bytes calldata inputProof
    ) public virtual {
        require(fromToken.isOperator(msg.sender, address(this)));

        euint64 amount = TFHE.asEuint64(amountInput, inputProof);

        TFHE.allowTransient(amount, address(fromToken));
        euint64 amountTransferred = fromToken.confidentialTransferFrom(msg.sender, address(this), amount);

        TFHE.allowTransient(amountTransferred, address(toToken));
        toToken.confidentialTransfer(msg.sender, amountTransferred);
    }
}
