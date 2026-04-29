// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {ERC7984BalanceCapHookModule} from "../../../../token/ERC7984/utils/ERC7984BalanceCapHookModule.sol";

contract ERC7984BalanceCapHookModuleMock is ERC7984BalanceCapHookModule, ZamaEthereumConfig {}
