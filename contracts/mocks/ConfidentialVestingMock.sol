// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {VestingConfidential} from "../finance/VestingConfidential.sol";
import {ConfidentialFungibleToken} from "../token/ConfidentialFungibleToken.sol";

contract VestingConfidentialMock is VestingConfidential, SepoliaConfig {
    constructor(ConfidentialFungibleToken token) VestingConfidential(token) {}
}
