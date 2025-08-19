// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ConfidentialFungibleTokenCustodianAccess, ConfidentialFungibleToken} from "../../token/extensions/ConfidentialFungibleTokenCustodianAccess.sol";
import {ConfidentialFungibleTokenMock} from "./ConfidentialFungibleTokenMock.sol";

contract ConfidentialFungibleTokenCustodianAccessMock is
    ConfidentialFungibleTokenCustodianAccess,
    ConfidentialFungibleTokenMock
{
    constructor(
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) ConfidentialFungibleTokenMock(name_, symbol_, tokenURI_) {}

    function _update(
        address from,
        address to,
        euint64 amount
    )
        internal
        virtual
        override(ConfidentialFungibleTokenCustodianAccess, ConfidentialFungibleTokenMock)
        returns (euint64)
    {
        return super._update(from, to, amount);
    }
}
