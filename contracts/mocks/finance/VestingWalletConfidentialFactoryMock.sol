// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SepoliaConfig, ZamaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7821WithExecutor} from "./../../finance/ERC7821WithExecutor.sol";
import {VestingWalletCliffConfidential} from "./../../finance/VestingWalletCliffConfidential.sol";
import {VestingWalletConfidentialFactory} from "./../../finance/VestingWalletConfidentialFactory.sol";

abstract contract VestingWalletConfidentialFactoryMock is VestingWalletConfidentialFactory, SepoliaConfig {
    function _deployVestingWalletImplementation() internal virtual override returns (address) {
        return address(new VestingWalletCliffExecutorConfidential());
    }

    function _initializeVestingWallet(
        address vestingWalletAddress,
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds,
        address executor
    ) internal virtual override {
        VestingWalletCliffExecutorConfidential(vestingWalletAddress).initialize(
            beneficiary,
            startTimestamp,
            durationSeconds,
            cliffSeconds,
            executor
        );
    }
}

// slither-disable-next-line locked-ether
contract VestingWalletCliffExecutorConfidential is VestingWalletCliffConfidential, ERC7821WithExecutor, SepoliaConfig {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds,
        address executor
    ) public initializer {
        __VestingWalletConfidential_init(beneficiary, startTimestamp, durationSeconds);
        __VestingWalletCliffConfidential_init(cliffSeconds);
        __ERC7821WithExecutor_init(executor);

        FHE.setCoprocessor(ZamaConfig.getSepoliaConfig());
        FHE.setDecryptionOracle(ZamaConfig.getSepoliaOracleAddress());
    }
}
