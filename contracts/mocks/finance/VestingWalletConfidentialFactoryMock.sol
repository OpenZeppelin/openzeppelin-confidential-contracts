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

    function _validateVestingWalletInitArgs(bytes memory initArgs) internal virtual override {
        // solhint-disable no-unused-vars
        (
            address beneficiary,
            uint48 startTimestamp,
            uint48 durationSeconds,
            uint48 cliffSeconds,
            address executor
        ) = abi.decode(initArgs, (address, uint48, uint48, uint48, address));

        require(cliffSeconds <= durationSeconds);
        require(beneficiary != address(0));
    }

    function _initializeVestingWallet(address vestingWalletAddress, bytes calldata initArgs) internal virtual override {
        (
            address beneficiary,
            uint48 startTimestamp,
            uint48 durationSeconds,
            uint48 cliffSeconds,
            address executor
        ) = abi.decode(initArgs, (address, uint48, uint48, uint48, address));

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
        __VestingWalletCliffConfidential_init(beneficiary, startTimestamp, durationSeconds, cliffSeconds);
        __ERC7821WithExecutor_init(executor);

        FHE.setCoprocessor(ZamaConfig.getSepoliaConfig());
    }
}
