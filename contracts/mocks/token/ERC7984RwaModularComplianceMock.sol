// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {ERC7984} from "../../token/ERC7984/ERC7984.sol";
import {ERC7984Rwa} from "../../token/ERC7984/extensions/ERC7984Rwa.sol";
import {ERC7984RwaModularCompliance} from "../../token/ERC7984/extensions/rwa/ERC7984RwaModularCompliance.sol";

contract ERC7984RwaModularComplianceMock is ERC7984RwaModularCompliance, SepoliaConfig {
    constructor(
        string memory name,
        string memory symbol,
        string memory tokenUri,
        address admin
    ) ERC7984Rwa(admin) ERC7984(name, symbol, tokenUri) {}
}
