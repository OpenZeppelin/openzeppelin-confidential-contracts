// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint64, externalEuint64, euint128} from "@fhevm/solidity/lib/FHE.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IConfidentialFungibleToken} from "./../interfaces/IConfidentialFungibleToken.sol";
import {ERC7821WithExecutor} from "./ERC7821WithExecutor.sol";
import {VestingWalletCliffConfidential} from "./VestingWalletCliffConfidential.sol";
import {VestingWalletConfidential} from "./VestingWalletConfidential.sol";

/**
 * @dev This factory enables creating {VestingWalletCliffExecutorConfidential} in batch.
 *
 * Confidential vesting wallets created inherit both {VestingWalletCliffConfidential} for vesting cliffs
 * and {ERC7821WithExecutor} to allow for arbitrary calls to be executed from the vesting wallet.
 */
contract VestingWalletCliffExecutorConfidentialFactory {
    struct VestingPlan {
        address beneficiary;
        externalEuint64 encryptedAmount;
        uint48 startTimestamp;
        uint48 durationSeconds;
        uint48 cliffSeconds;
    }

    address private immutable _vestingImplementation = address(new VestingWalletCliffExecutorConfidential());

    event VestingWalletConfidentialFunded(
        address indexed vestingWalletConfidential,
        address indexed beneficiary,
        address indexed confidentialFungibleToken,
        euint64 encryptedAmount,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds,
        address executor
    );
    event VestingWalletConfidentialCreated(
        address indexed vestingWalletConfidential,
        address indexed beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds,
        address indexed executor
    );

    /**
     * @dev Batches the funding of multiple confidential vesting wallets.
     *
     * Funds are sent to deterministic wallet addresses. Wallets can be created either
     * before or after this operation.
     *
     * Emits a {VestingWalletConfidentialFunded} event for each funded vesting plan.
     */
    function batchFundVestingWalletConfidential(
        address confidentialFungibleToken,
        VestingPlan[] calldata vestingPlans,
        address executor,
        bytes calldata inputProof
    ) public virtual {
        uint256 vestingPlansLength = vestingPlans.length;
        for (uint256 i = 0; i < vestingPlansLength; i++) {
            VestingPlan memory vestingPlan = vestingPlans[i];
            require(
                vestingPlan.cliffSeconds <= vestingPlan.durationSeconds,
                VestingWalletCliffConfidential.VestingWalletCliffConfidentialInvalidCliffDuration(
                    vestingPlan.cliffSeconds,
                    vestingPlan.durationSeconds
                )
            );

            require(vestingPlan.beneficiary != address(0), OwnableUpgradeable.OwnableInvalidOwner(address(0)));
            address vestingWalletAddress = predictVestingWalletConfidential(
                vestingPlan.beneficiary,
                vestingPlan.startTimestamp,
                vestingPlan.durationSeconds,
                vestingPlan.cliffSeconds,
                executor
            );

            euint64 transferredAmount;
            {
                // avoiding stack too deep with scope
                euint64 encryptedAmount = FHE.fromExternal(vestingPlan.encryptedAmount, inputProof);
                FHE.allowTransient(encryptedAmount, confidentialFungibleToken);
                transferredAmount = IConfidentialFungibleToken(confidentialFungibleToken).confidentialTransferFrom(
                    msg.sender,
                    vestingWalletAddress,
                    encryptedAmount
                );
            }

            emit VestingWalletConfidentialFunded(
                vestingWalletAddress,
                vestingPlan.beneficiary,
                confidentialFungibleToken,
                transferredAmount,
                vestingPlan.startTimestamp,
                vestingPlan.durationSeconds,
                vestingPlan.cliffSeconds,
                executor
            );
        }
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

// slither-disable-next-line locked-ether
contract VestingWalletCliffExecutorConfidential is VestingWalletCliffConfidential, ERC7821WithExecutor {
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
    }
}
