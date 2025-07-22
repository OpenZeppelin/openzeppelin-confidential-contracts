// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ConfidentialFungibleTokenMock} from "./ConfidentialFungibleTokenMock.sol";

// solhint-disable func-name-mixedcase
contract ConfidentialFungibleTokenReentrantMock is ConfidentialFungibleTokenMock {
    constructor(
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) ConfidentialFungibleTokenMock(name_, symbol_, tokenURI_) {}

    function confidentialTransfer(address, euint64) public override returns (euint64 transferred) {
        IVestingWalletConfidential(msg.sender).release(address(this));
        transferred;
    }
}

interface IVestingWalletConfidential {
    function release(address token) external;
}
