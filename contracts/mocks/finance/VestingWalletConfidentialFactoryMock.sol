// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {VestingWalletCliffExecutorConfidentialFactory} from "../../finance/VestingWalletCliffExecutorConfidentialFactory.sol";

abstract contract VestingWalletCliffExecutorConfidentialFactoryMock is
    VestingWalletCliffExecutorConfidentialFactory,
    SepoliaConfig
{}
