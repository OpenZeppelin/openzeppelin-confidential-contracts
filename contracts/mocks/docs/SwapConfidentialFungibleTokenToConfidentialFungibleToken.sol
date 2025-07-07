// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IConfidentialFungibleToken} from "../../interfaces/IConfidentialFungibleToken.sol";

contract SwapConfidentialFungibleTokenToConfidentialFungibleToken {
    function swapConfidentialForConfidential(
        IConfidentialFungibleToken fromToken,
        IConfidentialFungibleToken toToken,
        externalEuint64 amountInput,
        bytes calldata inputProof
    ) public virtual {
        require(fromToken.isOperator(msg.sender, address(this)));

        euint64 amount = FHE.fromExternal(amountInput, inputProof);

        FHE.allowTransient(amount, address(fromToken));
        euint64 amountTransferred = fromToken.transferFrom(msg.sender, address(this), amount);

        FHE.allowTransient(amountTransferred, address(toToken));
        toToken.transfer(msg.sender, amountTransferred);
    }
}
