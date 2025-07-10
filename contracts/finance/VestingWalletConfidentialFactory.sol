// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IConfidentialFungibleToken} from "../interfaces/IConfidentialFungibleToken.sol";
import {VestingWalletCliffConfidential} from "./VestingWalletCliffConfidential.sol";
import {VestingWalletConfidential} from "./VestingWalletConfidential.sol";
import {VestingWalletExecutorConfidential} from "./VestingWalletExecutorConfidential.sol";

abstract contract VestingWalletConfidentialFactory {
    address private immutable _vestingWalletConfidentialImplementation;

    error VestingWalletConfidentialInvalidDuration();
    error VestingWalletConfidentialInvalidStartTimestamp(address beneficiary, uint64 startTimestamp);

    /**
     * @dev
     */
    event VestingWalletConfidentialBatchFunded(ebool success);
    /**
     * @dev
     */
    event VestingWalletConfidentialCreated(
        address indexed beneficiary,
        address indexed vestingWalletConfidential,
        uint48 startTimestamp
    );

    /**
     * @dev
     */
    struct VestingPlan {
        address beneficiary;
        externalEuint64 encryptedAmount;
        uint48 startTimestamp;
        uint48 cliff;
        address executor;
    }

    /**
     * @dev
     */
    constructor() {
        _vestingWalletConfidentialImplementation = address(new VestingWalletCliffExecutorConfidential());
    }

    /**
     * @dev Batches the funding of multiple confidential vesting wallets.
     *
     * Funds are sent to predeterministic wallet addresses. Wallets can be created later.
     */
    function batchFundVestingWalletConfidential(
        address confidentialFungibleToken,
        externalEuint64 totalEncryptedAmount,
        bytes calldata inputProof,
        VestingPlan[] calldata vestingPlans,
        uint48 durationSeconds
    ) external returns (ebool) {
        require(durationSeconds > 0, VestingWalletConfidentialInvalidDuration());
        euint64 totalTransferedAmount = euint64.wrap(0);
        uint256 vestingPlansLength = vestingPlans.length;
        for (uint256 i = 0; i < vestingPlansLength; i++) {
            VestingPlan memory vestingPlan = vestingPlans[i];
            euint64 encryptedAmount = FHE.fromExternal(vestingPlan.encryptedAmount, inputProof);
            require(
                vestingPlan.startTimestamp >= block.timestamp,
                VestingWalletConfidentialInvalidStartTimestamp(vestingPlan.beneficiary, vestingPlan.startTimestamp)
            );
            address vestingWalletConfidential = predictVestingWalletConfidential(
                vestingPlan.beneficiary,
                vestingPlan.startTimestamp,
                durationSeconds,
                vestingPlan.cliff,
                vestingPlan.executor
            );
            FHE.allow(encryptedAmount, confidentialFungibleToken);
            euint64 transferredAmount = IConfidentialFungibleToken(confidentialFungibleToken).confidentialTransferFrom(
                msg.sender,
                vestingWalletConfidential,
                encryptedAmount
            );
            totalTransferedAmount = FHE.select(
                FHE.eq(encryptedAmount, transferredAmount),
                FHE.add(totalTransferedAmount, transferredAmount),
                FHE.asEuint64(0)
            );
        }
        // Revert batch if one failed?
        ebool success = FHE.eq(totalTransferedAmount, FHE.fromExternal(totalEncryptedAmount, inputProof));
        emit VestingWalletConfidentialBatchFunded(success);
    }

    /**
     * @dev Creates a confidential vesting wallet.
     */
    function createVestingWalletConfidential(
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds,
        address executor
    ) external returns (address) {
        // TODO: Check params are authorized
        // Will revert if clone already created
        address vestingWalletConfidentialAddress = Clones.cloneDeterministicWithImmutableArgs(
            _vestingWalletConfidentialImplementation,
            abi.encodePacked(beneficiary, startTimestamp, durationSeconds, cliffSeconds, executor),
            _getCreate2VestingWalletConfidentialSalt(beneficiary, startTimestamp)
        );
        VestingWalletCliffExecutorConfidential(vestingWalletConfidentialAddress).initialize(
            beneficiary,
            startTimestamp,
            durationSeconds,
            cliffSeconds,
            executor
        );
        emit VestingWalletConfidentialCreated(beneficiary, vestingWalletConfidentialAddress, startTimestamp);
        return vestingWalletConfidentialAddress;
    }

    /**
     * @dev
     */
    function predictVestingWalletConfidential(
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliff,
        address executor
    ) public view returns (address) {
        return
            Clones.predictDeterministicAddressWithImmutableArgs(
                _vestingWalletConfidentialImplementation,
                abi.encodePacked(beneficiary, startTimestamp, durationSeconds, cliff, executor),
                _getCreate2VestingWalletConfidentialSalt(beneficiary, startTimestamp),
                address(this)
            );
    }

    /**
     * @dev Gets create2 VestingWalletConfidential salt.
     */
    function _getCreate2VestingWalletConfidentialSalt(
        address beneficiary,
        uint48 startTimestamp
    ) internal pure virtual returns (bytes32) {
        return keccak256(abi.encodePacked(beneficiary, startTimestamp));
    }
}

contract VestingWalletCliffExecutorConfidential is VestingWalletCliffConfidential, VestingWalletExecutorConfidential {
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
        __VestingWalletExecutorConfidential_init(executor);
    }

    function _vestingSchedule(
        euint64 totalAllocation,
        uint64 timestamp
    ) internal override(VestingWalletCliffConfidential, VestingWalletConfidential) returns (euint64) {
        return super._vestingSchedule(totalAllocation, timestamp);
    }
}
