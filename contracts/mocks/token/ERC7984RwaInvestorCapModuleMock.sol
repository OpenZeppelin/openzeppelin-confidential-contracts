// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {ERC7984RwaInvestorCapModule} from "../../token/ERC7984/extensions/rwa/ERC7984RwaInvestorCapModule.sol";

contract ERC7984RwaInvestorCapModuleMock is ERC7984RwaInvestorCapModule, ZamaEthereumConfig {}
