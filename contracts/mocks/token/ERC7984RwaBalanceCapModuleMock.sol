// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984RwaBalanceCapModule} from "../../token/ERC7984/extensions/rwa/ERC7984RwaBalanceCapModule.sol";

contract ERC7984RwaBalanceCapModuleMock is ERC7984RwaBalanceCapModule, ZamaEthereumConfig {}
