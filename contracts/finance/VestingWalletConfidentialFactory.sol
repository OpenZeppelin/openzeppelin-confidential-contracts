// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint64, externalEuint64, euint128} from "@fhevm/solidity/lib/FHE.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IConfidentialFungibleToken} from "./../interfaces/IConfidentialFungibleToken.sol";
import {VestingWalletCliffConfidential} from "./VestingWalletCliffConfidential.sol";

/**
 * @dev A factory which enables batch funding of vesting wallets.
 *
 * The {_deployVestingWalletImplementation} and {_initializeVestingWallet} functions remain unimplemented
 * to allow for custom implementations of the vesting wallet to be used.
 */
abstract contract VestingWalletConfidentialFactory {
    struct VestingPlan {
        address beneficiary;
        externalEuint64 encryptedAmount;
        uint48 startTimestamp;
        uint48 durationSeconds;
        uint48 cliffSeconds;
    }

    address private immutable _vestingImplementation;

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

    constructor() {
        _vestingImplementation = _deployVestingWalletImplementation();
    }

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
        _initializeVestingWallet(
            vestingWalletConfidentialAddress,
            beneficiary,
            startTimestamp,
            durationSeconds,
            cliffSeconds,
            executor
        );
        emit VestingWalletConfidentialCreated(
            vestingWalletConfidentialAddress,
            beneficiary,
            startTimestamp,
            durationSeconds,
            cliffSeconds,
            executor
        );
        return vestingWalletConfidentialAddress;
    }

    /**
     * @dev Predicts the deterministic address for a confidential vesting wallet.
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

    /// @dev Virtual function that must be implemented to initialize the vesting wallet at `vestingWalletAddress`.
    function _initializeVestingWallet(
        address vestingWalletAddress,
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds,
        address executor
    ) internal virtual;

    /**
     * @dev Internal function that is called once to deploy the vesting wallet implementation.
     *
     * Vesting wallet clones will be initialized by calls to the {_initializeVestingWallet} function.
     */
    function _deployVestingWalletImplementation() internal virtual returns (address);

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
