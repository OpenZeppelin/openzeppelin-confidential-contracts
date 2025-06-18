// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TFHE, einput, ebool, euint64} from "fhevm/lib/TFHE.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ConfidentialFungibleToken} from "../../token/ConfidentialFungibleToken.sol";

contract ConfidentialFungibleTokenMintableBurnable is ConfidentialFungibleToken, Ownable {
    using TFHE for *;

    constructor(
        address owner,
        string memory name,
        string memory symbol,
        string memory uri
    ) ConfidentialFungibleToken(name, symbol, uri) Ownable(owner) {}

    function mint(address to, einput amount, bytes memory inputProof) public onlyOwner {
        _mint(to, amount.asEuint64(inputProof));
    }

    function burn(address from, einput amount, bytes memory inputProof) public onlyOwner {
        _burn(from, amount.asEuint64(inputProof));
    }
}
