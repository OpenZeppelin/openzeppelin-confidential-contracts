// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialVesting } from "../finance/ConfidentialVesting.sol";
import { ConfidentialFungibleToken } from "../token/ConfidentialFungibleToken.sol";

contract ConfidentialVestingMock is ConfidentialVesting, SepoliaZamaFHEVMConfig {
    constructor(ConfidentialFungibleToken token) ConfidentialVesting(token) {}
}
