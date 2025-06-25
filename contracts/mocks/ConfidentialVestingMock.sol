// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SepoliaZamaFHEVMConfig} from "fhevm/config/ZamaFHEVMConfig.sol";
import {VestingConfidential} from "../finance/VestingConfidential.sol";
import {ConfidentialFungibleToken} from "../token/ConfidentialFungibleToken.sol";

contract VestingConfidentialMock is VestingConfidential, SepoliaZamaFHEVMConfig {
    constructor(ConfidentialFungibleToken token) VestingConfidential(token) {}
}
