// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, euint128, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IConfidentialFungibleToken} from "../interfaces/IConfidentialFungibleToken.sol";
import {VestingWalletCliffConfidential} from "./VestingWalletCliffConfidential.sol";
import {VestingWalletConfidential} from "./VestingWalletConfidential.sol";
import {VestingWalletExecutorConfidential} from "./VestingWalletExecutorConfidential.sol";

/**
 * @dev This factory enables creating {VestingWalletCliffExecutorConfidential} in batch.
 *
 * All confidential vesting wallets created support both "cliff" ({VestingWalletCliffConfidential})
 * and "executor" ({VestingWalletExecutorConfidential}) extensions.
 */
abstract contract VestingWalletConfidentialFactory {
    address private immutable _vestingImplementation;

    /// @dev The specified cliff duration is larger than the vesting duration.
    error InvalidCliffDuration(address beneficiary, uint64 cliffSeconds, uint64 durationSeconds);

    event VestingWalletConfidentialFunded(
        address indexed vestingWalletConfidential,
        address indexed beneficiary,
        address confidentialFungibleToken,
        euint64 encryptedAmount,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds,
        address executor
    );
    event VestingWalletConfidentialBatchFunded(address indexed from);
    event VestingWalletConfidentialCreated(
        address indexed vestingWalletConfidential,
        address indexed beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds,
        address executor
    );

    struct VestingPlan {
        address beneficiary;
        externalEuint64 encryptedAmount;
        uint48 start;
        uint48 cliff;
        address executor;
    }

    constructor() {
        _vestingImplementation = address(new VestingWalletCliffExecutorConfidential());
    }

    /**
     * @dev Batches the funding of multiple confidential vesting wallets.
     *
     * Funds are sent to predeterministic wallet addresses. Wallets can be created either
     * before or after this operation.
     *
     * Emits a single {VestingWalletConfidentialBatchFunded} event in addition to multiple
     * {VestingWalletConfidentialFunded} events related to funded vesting plans.
     */
    function batchFundVestingWalletConfidential(
        address confidentialFungibleToken,
        VestingPlan[] calldata vestingPlans,
        uint48 durationSeconds,
        bytes calldata inputProof
    ) public virtual returns (bool) {
        for (uint256 i = 0; i < vestingPlans.length; i++) {
            VestingPlan memory vestingPlan = vestingPlans[i];
            euint64 encryptedAmount = FHE.fromExternal(vestingPlan.encryptedAmount, inputProof);
            require(
                vestingPlan.cliff <= durationSeconds,
                InvalidCliffDuration(vestingPlan.beneficiary, vestingPlan.cliff, durationSeconds)
            );
            address vestingWalletConfidential = predictVestingWalletConfidential(
                vestingPlan.beneficiary,
                vestingPlan.start,
                durationSeconds,
                vestingPlan.cliff,
                vestingPlan.executor
            );
            FHE.allowTransient(encryptedAmount, confidentialFungibleToken);
            euint64 transferredAmount = IConfidentialFungibleToken(confidentialFungibleToken).confidentialTransferFrom(
                msg.sender,
                vestingWalletConfidential,
                encryptedAmount
            );
            emit VestingWalletConfidentialFunded(
                vestingWalletConfidential,
                vestingPlan.beneficiary,
                confidentialFungibleToken,
                transferredAmount,
                vestingPlan.start,
                durationSeconds,
                vestingPlan.cliff,
                vestingPlan.executor
            );
        }
        emit VestingWalletConfidentialBatchFunded(msg.sender);
        return true;
    }

    /**
     * @dev Creates a confidential vesting wallet.
     *
     * Emits a {VestingWalletConfidentialCreated}.
     */
    function createVestingWalletConfidential(
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds,
        address executor
    ) public virtual returns (address) {
        // Will revert if clone already created
        address vestingWalletConfidentialAddress = Clones.cloneDeterministic(
            _vestingImplementation,
            _getCreate2VestingWalletConfidentialSalt(
                beneficiary,
                startTimestamp,
                durationSeconds,
                cliffSeconds,
                executor
            )
        );
        VestingWalletCliffExecutorConfidential(vestingWalletConfidentialAddress).initialize(
            beneficiary,
            startTimestamp,
            durationSeconds,
            cliffSeconds,
            executor
        );
        emit VestingWalletConfidentialCreated(
            beneficiary,
            vestingWalletConfidentialAddress,
            startTimestamp,
            durationSeconds,
            cliffSeconds,
            executor
        );
        return vestingWalletConfidentialAddress;
    }

    /**
     * @dev Predicts deterministic address for a confidential vesting wallet.
     */
    function predictVestingWalletConfidential(
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds,
        address executor
    ) public view virtual returns (address) {
        return
            Clones.predictDeterministicAddress(
                _vestingImplementation,
                _getCreate2VestingWalletConfidentialSalt(
                    beneficiary,
                    startTimestamp,
                    durationSeconds,
                    cliffSeconds,
                    executor
                )
            );
    }

    /**
     * @dev Gets create2 salt for a confidential vesting wallet.
     */
    function _getCreate2VestingWalletConfidentialSalt(
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds,
        address executor
    ) internal pure virtual returns (bytes32) {
        return keccak256(abi.encodePacked(beneficiary, startTimestamp, durationSeconds, cliffSeconds, executor));
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
        euint128 totalAllocation,
        uint64 timestamp
    ) internal override(VestingWalletCliffConfidential, VestingWalletConfidential) returns (euint128) {
        return super._vestingSchedule(totalAllocation, timestamp);
    }
}
