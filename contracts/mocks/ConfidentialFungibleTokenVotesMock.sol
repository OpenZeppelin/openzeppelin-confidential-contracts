// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ConfidentialFungibleTokenVotes, ConfidentialFungibleToken, VotesConfidential} from "../token/extensions/ConfidentialFungibleTokenVotes.sol";
import {ConfidentialFungibleTokenMock} from "./ConfidentialFungibleTokenMock.sol";

abstract contract ConfidentialFungibleTokenVotesMock is ConfidentialFungibleTokenMock, ConfidentialFungibleTokenVotes {
    address private immutable _OWNER;

    uint48 private _clockOverrideVal;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) ConfidentialFungibleTokenMock(name_, symbol_, tokenURI_) EIP712(name_, "1.0.0") {
        _OWNER = msg.sender;
    }

    function clock() public view virtual override returns (uint48) {
        if (_clockOverrideVal != 0) {
            return _clockOverrideVal;
        }
        return super.clock();
    }

    function totalSupply()
        public
        view
        virtual
        override(ConfidentialFungibleToken, ConfidentialFungibleTokenVotes)
        returns (euint64)
    {
        return super.totalSupply();
    }

    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ConfidentialFungibleTokenMock, ConfidentialFungibleTokenVotes) returns (euint64) {
        return super._update(from, to, amount);
    }

    function _setClockOverride(uint48 val) external {
        _clockOverrideVal = val;
    }
}
