// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {BalanceCapComplianceModuleConfidential} from "../../../token/ERC7984/utils/BalanceCapComplianceModuleConfidential.sol";

contract BalanceCapComplianceModuleConfidentialMock is BalanceCapComplianceModuleConfidential, ZamaEthereumConfig {}
