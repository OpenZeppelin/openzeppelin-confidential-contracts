// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {BatcherConfidential} from "../../utils/BatcherConfidential.sol";

abstract contract BatcherConfidentialMock is ZamaEthereumConfig, BatcherConfidential {}
