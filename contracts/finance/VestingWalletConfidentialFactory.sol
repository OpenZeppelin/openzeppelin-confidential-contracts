// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IConfidentialFungibleToken} from "../interfaces/IConfidentialFungibleToken.sol";
import {VestingWalletExecutorConfidentialImpl} from "./VestingWalletExecutorConfidentialImpl.sol";

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
        address executor;
        address beneficiary;
        externalEuint64 encryptedAmount;
        uint48 startTimestamp;
    }

    /**
     * @dev
     */
    constructor() {
        _vestingWalletConfidentialImplementation = address(new VestingWalletExecutorConfidentialImpl());
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
                vestingPlan.executor,
                vestingPlan.beneficiary,
                vestingPlan.startTimestamp,
                durationSeconds
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
        address executor,
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds
    ) external returns (address) {
        // TODO: Check params are authorized
        // Will revert if clone already created
        address vestingWalletConfidentialAddress = Clones.cloneDeterministicWithImmutableArgs(
            _vestingWalletConfidentialImplementation,
            abi.encodePacked(executor, beneficiary, startTimestamp, durationSeconds),
            _getCreate2VestingWalletConfidentialSalt(beneficiary, startTimestamp)
        );
        VestingWalletExecutorConfidentialImpl(vestingWalletConfidentialAddress).initialize(
            executor,
            beneficiary,
            startTimestamp,
            durationSeconds
        );
        emit VestingWalletConfidentialCreated(beneficiary, vestingWalletConfidentialAddress, startTimestamp);
        return vestingWalletConfidentialAddress;
    }

    /**
     * @dev
     */
    function predictVestingWalletConfidential(
        address executor,
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds
    ) public view returns (address) {
        return
            Clones.predictDeterministicAddressWithImmutableArgs(
                _vestingWalletConfidentialImplementation,
                abi.encodePacked(executor, beneficiary, startTimestamp, durationSeconds),
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
