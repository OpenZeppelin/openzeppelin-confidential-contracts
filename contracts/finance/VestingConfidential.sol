// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {FHE, externalEuint64, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";

import {TFHESafeMath} from "../utils/TFHESafeMath.sol";
import {ManagedVault} from "./ManagedVault.sol";
import {ConfidentialFungibleToken} from "../token/ConfidentialFungibleToken.sol";

contract VestingConfidential {
    using FHE for *;

    struct VestingStream {
        uint48 startTime;
        address recipient;
        euint64 totalAmount;
        euint64 amountPerSecond;
        euint64 claimed;
    }

    event VestingConfidentialManagedVaultCreated(uint256 vestingStreamId, address managedVault);

    error VestingConfidentialOnlyRecipient(address recipient);
    error VestingConfidentialVaultNotDeployed(uint256 vestingId);

    address private immutable _managedVaultImplementation;
    ConfidentialFungibleToken private immutable _token;
    mapping(uint256 => VestingStream) private _vestingStreams;
    mapping(uint256 vestingId => address managedVault) private _managedVaults;
    uint256 private _numVestingStreams;

    constructor(ConfidentialFungibleToken token_) {
        _token = token_;
        _managedVaultImplementation = _createManagedVaultImplementation();
    }

    function claim(uint256 streamId) public virtual {
        address recipient = _vestingStreams[streamId].recipient;
        require(msg.sender == recipient, VestingConfidentialOnlyRecipient(recipient));
        _claim(streamId);
    }

    function getOrCreateManagedVault(uint256 streamId) public virtual returns (address) {
        address existingVault = getManagedVault(streamId);
        if (existingVault != address(0)) {
            return existingVault;
        }
        claim(streamId);
        return _setUpManagedVault(streamId);
    }

    function getManagedVault(uint256 streamId) public view virtual returns (address) {
        return _managedVaults[streamId];
    }

    function createVestingStream(
        uint48 startTime,
        address recipient,
        externalEuint64 totalAmount,
        externalEuint64 amountPerSecond,
        bytes memory amountInputProof,
        bytes memory amountPerSecondInputProof
    ) public virtual {
        _createVestingStream(
            startTime,
            recipient,
            totalAmount.fromExternal(amountInputProof),
            amountPerSecond.fromExternal(amountPerSecondInputProof)
        );
    }

    function token() public view virtual returns (ConfidentialFungibleToken) {
        return _token;
    }

    function _doTransferOut(address to, euint64 amount) internal virtual returns (euint64) {
        return _doTransferOut(address(this), to, amount);
    }

    function _doTransferOut(address from, address to, euint64 amount) internal virtual returns (euint64) {
        amount.allowTransient(address(token()));
        return token().confidentialTransferFrom(from, to, amount);
    }

    function _setUpManagedVault(uint256 streamId) internal virtual returns (address) {
        address recipient = _vestingStreams[streamId].recipient;
        require(recipient == msg.sender, VestingConfidentialOnlyRecipient(recipient));

        address vault = Clones.clone(_managedVaultImplementation);
        _managedVaults[streamId] = vault;

        (, euint64 amountToTransfer) = TFHESafeMath.tryDecrease(
            _vestingStreams[streamId].totalAmount,
            _vestingStreams[streamId].claimed
        );
        _doTransferOut(vault, amountToTransfer);

        emit VestingConfidentialManagedVaultCreated(streamId, vault);

        _managedVaultExecute(
            streamId,
            address(token()),
            0,
            abi.encodeCall(ConfidentialFungibleToken.setOperator, (address(this), type(uint48).max))
        );

        return vault;
    }

    function _createVestingStream(
        uint48 startTime,
        address recipient,
        euint64 amount,
        euint64 amountPerSecond
    ) internal virtual {
        amount.allowTransient(address(token()));

        euint64 amountTransferredIn = token().confidentialTransferFrom(msg.sender, address(this), amount);
        amountTransferredIn.allowThis();
        amountPerSecond.allowThis();

        _vestingStreams[++_numVestingStreams] = VestingStream({
            startTime: startTime,
            recipient: recipient,
            totalAmount: amountTransferredIn,
            amountPerSecond: amountPerSecond,
            claimed: euint64.wrap(0)
        });
    }

    function _claim(uint256 streamId) internal virtual {
        VestingStream storage stream = _vestingStreams[streamId];
        if (block.timestamp <= stream.startTime) return;

        (ebool success, euint64 claimAmount) = TFHESafeMath.tryDecrease(
            FHE.min(FHE.mul(stream.amountPerSecond, uint64(block.timestamp - stream.startTime)), stream.totalAmount),
            stream.claimed
        );

        euint64 amountToTransferOut = FHE.select(success, claimAmount, FHE.asEuint64(0));

        // If managed vault exists, do transfer out from there
        address managedVault = getManagedVault(streamId);
        euint64 amountTransferredOut;
        if (managedVault != address(0)) {
            amountTransferredOut = _doTransferOut(managedVault, stream.recipient, amountToTransferOut);
        } else {
            amountTransferredOut = _doTransferOut(stream.recipient, amountToTransferOut);
        }

        (, euint64 newAmountClaimed) = TFHESafeMath.tryIncrease(stream.claimed, amountTransferredOut);
        newAmountClaimed.allowThis();
        stream.claimed = newAmountClaimed;
    }

    function _createManagedVaultImplementation() internal virtual returns (address) {
        return address(new ManagedVault());
    }

    function _managedVaultExecute(uint256 streamId, address target, uint256 value, bytes memory data) internal virtual {
        address managedVault = getManagedVault(streamId);
        require(managedVault != address(0), VestingConfidentialVaultNotDeployed(streamId));

        ManagedVault(managedVault).call(target, value, data);
    }
}
