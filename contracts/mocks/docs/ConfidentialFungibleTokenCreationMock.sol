// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { ConfidentialFungibleToken } from "../../token/ConfidentialFungibleToken.sol";
import { SepoliaZamaGatewayConfig } from "fhevm/config/ZamaGatewayConfig.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";

contract ConfidentialFungibleTokenCreationMock is
    ConfidentialFungibleToken,
    SepoliaZamaFHEVMConfig,
    SepoliaZamaGatewayConfig
{
    constructor() ConfidentialFungibleToken("ConfidentialFungibleToken", "CFT", "https://example.com/metadata") {}
}
