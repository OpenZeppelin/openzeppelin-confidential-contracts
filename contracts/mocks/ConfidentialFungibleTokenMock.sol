// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { TFHE, euint64, einput } from "fhevm/lib/TFHE.sol";
import { ConfidentialFungibleToken } from "../token/ConfidentialFungibleToken.sol";
import { SepoliaZamaGatewayConfig } from "fhevm/config/ZamaGatewayConfig.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";

contract ConfidentialFungibleTokenMock is ConfidentialFungibleToken, SepoliaZamaFHEVMConfig, SepoliaZamaGatewayConfig {
    address private immutable _OWNER;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) ConfidentialFungibleToken(name_, symbol_, tokenURI_) {
        _OWNER = msg.sender;
    }

    function _update(address from, address to, euint64 amount) internal virtual override returns (euint64 transferred) {
        transferred = super._update(from, to, amount);
        TFHE.allow(totalSupply(), _OWNER);
    }

    function $_setOperator(address holder, address operator, uint48 until) public virtual {
        return _setOperator(holder, operator, until);
    }

    function $_mint(
        address to,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _mint(to, TFHE.asEuint64(encryptedAmount, inputProof));
    }

    function $_transfer(
        address from,
        address to,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _transfer(from, to, TFHE.asEuint64(encryptedAmount, inputProof));
    }

    function $_transferAndCall(
        address from,
        address to,
        einput encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public returns (euint64 transferred) {
        return _transferAndCall(from, to, TFHE.asEuint64(encryptedAmount, inputProof), data);
    }

    function $_burn(
        address from,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _burn(from, TFHE.asEuint64(encryptedAmount, inputProof));
    }

    function $_update(
        address from,
        address to,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64 transferred) {
        return _update(from, to, TFHE.asEuint64(encryptedAmount, inputProof));
    }
}
