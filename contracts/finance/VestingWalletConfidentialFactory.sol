// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.2.0) (finance/VestingWalletConfidentialFactory.sol)
pragma solidity ^0.8.27;

import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC7984} from "./../interfaces/IERC7984.sol";

/**
 * @dev A factory which enables batch funding of vesting wallets.
 *
 * The {_deployVestingWalletImplementation}, {_initializeVestingWallet}, and {_validateVestingWalletInitArgs}
 * functions remain unimplemented to allow for custom implementations of the vesting wallet to be used.
 */
abstract contract VestingWalletConfidentialFactory {
    struct VestingPlan {
        externalEuint64 encryptedAmount;
        bytes initArgs;
    }

    address private immutable _vestingImplementation;

    /// @dev Emitted for each vesting wallet funded within a batch.
    event VestingWalletConfidentialFunded(
        address indexed vestingWalletConfidential,
        address indexed token,
        euint64 transferredAmount,
        bytes initArgs
    );
    /// @dev Emitted when a vesting wallet is deployed.
    event VestingWalletConfidentialCreated(address indexed vestingWalletConfidential, bytes initArgs);

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
        address token,
        VestingPlan[] calldata vestingPlans,
        bytes calldata inputProof
    ) public virtual {
        uint256 vestingPlansLength = vestingPlans.length;
        for (uint256 i = 0; i < vestingPlansLength; i++) {
            VestingPlan memory vestingPlan = vestingPlans[i];
            _validateVestingWalletInitArgs(vestingPlan.initArgs);

            address vestingWalletAddress = predictVestingWalletConfidential(vestingPlan.initArgs);

            euint64 encryptedAmount = FHE.fromExternal(vestingPlan.encryptedAmount, inputProof);
            FHE.allowTransient(encryptedAmount, token);
            euint64 transferredAmount = IERC7984(token).confidentialTransferFrom(
                msg.sender,
                vestingWalletAddress,
                encryptedAmount
            );

            emit VestingWalletConfidentialFunded(vestingWalletAddress, token, transferredAmount, vestingPlan.initArgs);
        }
    }

    /**
     * @dev Creates a confidential vesting wallet.
     *
     * Emits a {VestingWalletConfidentialCreated}.
     */
    function createVestingWalletConfidential(bytes calldata initArgs) public virtual returns (address) {
        // Will revert if clone already created
        address vestingWalletConfidentialAddress = Clones.cloneDeterministic(
            _vestingImplementation,
            _getCreate2VestingWalletConfidentialSalt(initArgs)
        );
        _initializeVestingWallet(vestingWalletConfidentialAddress, initArgs);
        emit VestingWalletConfidentialCreated(vestingWalletConfidentialAddress, initArgs);
        return vestingWalletConfidentialAddress;
    }

    /**
     * @dev Predicts the deterministic address for a confidential vesting wallet.
     */
    function predictVestingWalletConfidential(bytes memory initArgs) public view virtual returns (address) {
        return
            Clones.predictDeterministicAddress(
                _vestingImplementation,
                _getCreate2VestingWalletConfidentialSalt(initArgs)
            );
    }

    /// @dev Virtual function that must be implemented to validate the initArgs bytes.
    function _validateVestingWalletInitArgs(bytes memory initArgs) internal virtual;

    /// @dev Virtual function that must be implemented to initialize the vesting wallet at `vestingWalletAddress`.
    function _initializeVestingWallet(address vestingWalletAddress, bytes calldata initArgs) internal virtual;

    /**
     * @dev Internal function that is called once to deploy the vesting wallet implementation.
     *
     * Vesting wallet clones will be initialized by calls to the {_initializeVestingWallet} function.
     */
    function _deployVestingWalletImplementation() internal virtual returns (address);

    /**
     * @dev Gets create2 salt for a confidential vesting wallet.
     */
    function _getCreate2VestingWalletConfidentialSalt(bytes memory initArgs) internal pure virtual returns (bytes32) {
        return keccak256(initArgs);
    }
}
