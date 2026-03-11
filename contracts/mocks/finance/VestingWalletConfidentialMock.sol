// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {VestingWalletConfidential} from "../../finance/VestingWalletConfidential.sol";

abstract contract VestingWalletConfidentialMock is VestingWalletConfidential, ZamaEthereumConfig {}
