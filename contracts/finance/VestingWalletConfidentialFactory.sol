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
        externalEuint64 encryptedAmount;
        bytes initialization;
    }

    address private immutable _vestingImplementation;

    event VestingWalletConfidentialFunded(
        address indexed vestingWalletConfidential,
        address indexed confidentialFungibleToken,
        euint64 transferredAmount,
        bytes initialization
    );
    event VestingWalletConfidentialCreated(address indexed vestingWalletConfidential, bytes initialization);

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
        bytes calldata inputProof
    ) public virtual {
        uint256 vestingPlansLength = vestingPlans.length;
        for (uint256 i = 0; i < vestingPlansLength; i++) {
            VestingPlan memory vestingPlan = vestingPlans[i];
            _validateVestingWalletInitialization(vestingPlan.initialization);

            address vestingWalletAddress = predictVestingWalletConfidential(vestingPlan.initialization);

            euint64 encryptedAmount = FHE.fromExternal(vestingPlan.encryptedAmount, inputProof);
            FHE.allowTransient(encryptedAmount, confidentialFungibleToken);
            euint64 transferredAmount = IConfidentialFungibleToken(confidentialFungibleToken).confidentialTransferFrom(
                msg.sender,
                vestingWalletAddress,
                encryptedAmount
            );

            emit VestingWalletConfidentialFunded(
                vestingWalletAddress,
                confidentialFungibleToken,
                transferredAmount,
                vestingPlan.initialization
            );
        }
    }

    /**
     * @dev Creates a confidential vesting wallet.
     *
     * Emits a {VestingWalletConfidentialCreated}.
     */
    function createVestingWalletConfidential(bytes calldata initialization) public virtual returns (address) {
        // Will revert if clone already created
        address vestingWalletConfidentialAddress = Clones.cloneDeterministic(
            _vestingImplementation,
            _getCreate2VestingWalletConfidentialSalt(initialization)
        );
        _initializeVestingWallet(vestingWalletConfidentialAddress, initialization);
        emit VestingWalletConfidentialCreated(vestingWalletConfidentialAddress, initialization);
        return vestingWalletConfidentialAddress;
    }

    /**
     * @dev Predicts the deterministic address for a confidential vesting wallet.
     */
    function predictVestingWalletConfidential(bytes memory initialization) public view virtual returns (address) {
        return
            Clones.predictDeterministicAddress(
                _vestingImplementation,
                _getCreate2VestingWalletConfidentialSalt(initialization)
            );
    }

    /// @dev Virtual function that must be implemented to validate the initialization bytes.
    function _validateVestingWalletInitialization(bytes memory initialization) internal virtual;

    /// @dev Virtual function that must be implemented to initialize the vesting wallet at `vestingWalletAddress`.
    function _initializeVestingWallet(address vestingWalletAddress, bytes calldata initialization) internal virtual;

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
        bytes memory initialization
    ) internal pure virtual returns (bytes32) {
        return keccak256(initialization);
    }
}
