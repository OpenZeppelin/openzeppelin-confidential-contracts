// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ConfidentialFungibleTokenCustodianAccess, ConfidentialFungibleToken} from "../../token/extensions/ConfidentialFungibleTokenCustodianAccess.sol";

// solhint-disable func-name-mixedcase
contract ConfidentialFungibleTokenCustodianAccessMock is ConfidentialFungibleTokenCustodianAccess, SepoliaConfig {
    address private immutable _OWNER;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) ConfidentialFungibleToken(name_, symbol_, tokenURI_) {
        _OWNER = msg.sender;
    }

    function $_mint(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _mint(to, FHE.fromExternal(encryptedAmount, inputProof));
    }
}
