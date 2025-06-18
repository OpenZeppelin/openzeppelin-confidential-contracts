// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ManagedVault } from "./ManagedVault.sol";

abstract contract VestingBase {
    struct VestingStream {
        uint48 startTime;
        address recipient;
        uint256 totalAmount;
        uint256 amountPerSecond;
        uint256 claimed;
    }

    error VestingBaseMangedVaultAlreadyExists(uint256 vestingStream, address managedVault);
    error VestingBaseOnlyRecipient(address recipient);

    event VestingBaseManagedVaultCreated(uint256 vestingStreamId, address managedVault);

    mapping(uint256 => VestingStream) private _vestingStreams;
    mapping(uint256 vestingId => address managedVault) private _managedVaults;
    address private _managedVaultImplementation = address(new ManagedVault());
    uint256 numVestingStreams;

    function claim(uint256 streamId) public virtual {
        require(msg.sender == _vestingStreams[streamId].recipient);
        _claim(streamId);
    }

    function createManagedVault(uint256 streamId) public virtual returns (address) {
        return _createManagedVault(streamId);
    }

    function _doTransferIn(address from, uint256 amount) internal virtual returns (uint256);

    function _doTransferOut(address to, uint256 amount) internal virtual returns (uint256);

    function _doTransferOut(address from, address to, uint256 amount) internal virtual returns (uint256);

    function _mul(uint256 a, uint256 b) internal virtual returns (uint256);

    function _sub(uint256 a, uint256 b) internal virtual returns (uint256);

    function _add(uint256 a, uint256 b) internal virtual returns (uint256);

    function _min(uint256 a, uint256 b) internal virtual returns (uint256);

    function _prestore(uint256 a) internal virtual returns (uint256) {}

    function _createVestingStream(
        uint48 startTime,
        address recipient,
        uint256 amount,
        uint256 amountPerSecond
    ) internal {
        uint256 amountTransferredIn = _doTransferIn(msg.sender, amount);

        _vestingStreams[++numVestingStreams] = VestingStream({
            startTime: startTime,
            recipient: recipient,
            totalAmount: _prestore(_min(amountTransferredIn, amount)),
            amountPerSecond: _prestore(amountPerSecond),
            claimed: 0
        });
    }

    function _claim(uint256 streamId) internal virtual {
        VestingStream storage stream = _vestingStreams[streamId];
        uint256 claimAmount = _sub(
            _min(_mul(block.timestamp - stream.startTime, stream.amountPerSecond), stream.totalAmount),
            stream.claimed
        );

        uint256 amountTransferredOut;

        // If managed vault exists, do transfer out from there
        address managedVault = _managedVaults[streamId];
        if (managedVault != address(0)) {
            amountTransferredOut = _doTransferOut(managedVault, stream.recipient, claimAmount);
        } else {
            amountTransferredOut = _doTransferOut(stream.recipient, claimAmount);
        }

        stream.claimed = _prestore(_add(stream.claimed, amountTransferredOut));
    }

    function _createManagedVault(uint256 streamId) internal virtual returns (address) {
        address existingVault = _managedVaults[streamId];
        require(existingVault == address(0), VestingBaseMangedVaultAlreadyExists(streamId, existingVault));
        address recipient = _vestingStreams[streamId].recipient;
        require(recipient == msg.sender, VestingBaseOnlyRecipient(recipient));

        address vault = Clones.clone(_managedVaultImplementation);
        _managedVaults[streamId] = vault;

        _doTransferOut(vault, _vestingStreams[streamId].totalAmount - _vestingStreams[streamId].claimed);

        emit VestingBaseManagedVaultCreated(streamId, vault);

        return vault;
    }
}
