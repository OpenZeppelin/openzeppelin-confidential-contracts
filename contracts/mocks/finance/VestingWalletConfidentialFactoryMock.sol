// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {VestingWalletConfidentialFactory} from "../../finance/VestingWalletConfidentialFactory.sol";

abstract contract VestingWalletConfidentialFactoryMock is VestingWalletConfidentialFactory, SepoliaConfig {}
