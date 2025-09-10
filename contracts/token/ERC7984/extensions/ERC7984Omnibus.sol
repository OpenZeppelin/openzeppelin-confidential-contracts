// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, euint64, externalEuint64, externalEaddress, eaddress} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "../ERC7984.sol";

/**
 * @dev Extension of {ERC7984} that emits additional events for omnibus transfers.
 * These events contain encrypted addresses for the sub-account sender and recipient.
 *
 * NOTE: There is no onchain accounting for sub-accounts--integrators must track sub-account
 * balances externally.
 */
abstract contract ERC7984Omnibus is ERC7984 {
    /**
     * @dev Emitted when a confidential transfer is made representing the onchain settlement of
     * an omnibus transfer from `sender` to `recipient` of amount `amount`. Settlement occurs between
     * `omnibusFrom` and `omnibusTo` and is represented in a matching {ConfidentialTransfer} event.
     */
    event OmnibusConfidentialTransfer(
        address indexed omnibusFrom,
        address indexed omnibusTo,
        eaddress sender,
        eaddress indexed recipient,
        euint64 amount
    );

    function confidentialTransferOmnibus(
        address omnibusTo,
        externalEaddress externalSender,
        externalEaddress externalRecipient,
        externalEuint64 externalAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64) {
        eaddress sender = FHE.fromExternal(externalSender, inputProof);
        eaddress recipient = FHE.fromExternal(externalRecipient, inputProof);
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);

        return confidentialTransferOmnibus(omnibusTo, sender, recipient, amount);
    }

    function confidentialTransferOmnibus(
        address omnibusTo,
        eaddress sender,
        eaddress recipient,
        euint64 amount
    ) public virtual returns (euint64) {
        FHE.allowThis(recipient);
        FHE.allow(recipient, omnibusTo);
        FHE.allow(recipient, msg.sender);

        FHE.allowThis(sender);
        FHE.allow(sender, omnibusTo);
        FHE.allow(sender, msg.sender);

        euint64 transferred = confidentialTransfer(omnibusTo, amount);
        emit OmnibusConfidentialTransfer(msg.sender, omnibusTo, sender, recipient, transferred);
        return transferred;
    }

    function confidentialTransferFromOmnibus(
        address omnibusFrom,
        address omnibusTo,
        externalEaddress externalSender,
        externalEaddress externalRecipient,
        externalEuint64 externalAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64) {
        eaddress sender = FHE.fromExternal(externalSender, inputProof);
        eaddress recipient = FHE.fromExternal(externalRecipient, inputProof);
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);

        return confidentialTransferFromOmnibus(omnibusFrom, omnibusTo, sender, recipient, amount);
    }

    function confidentialTransferFromOmnibus(
        address omnibusFrom,
        address omnibusTo,
        eaddress sender,
        eaddress recipient,
        euint64 amount
    ) public virtual returns (euint64) {
        FHE.allowThis(sender);
        FHE.allow(sender, omnibusTo);
        FHE.allow(sender, omnibusFrom);

        FHE.allowThis(recipient);
        FHE.allow(recipient, omnibusTo);
        FHE.allow(recipient, omnibusFrom);

        euint64 transferred = confidentialTransferFrom(omnibusFrom, omnibusTo, amount);
        emit OmnibusConfidentialTransfer(omnibusFrom, omnibusTo, sender, recipient, transferred);
        return transferred;
    }

    function confidentialTransferAndCallOmnibus(
        address omnibusTo,
        externalEaddress externalSender,
        externalEaddress externalRecipient,
        externalEuint64 externalAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public virtual returns (euint64) {
        eaddress recipient = FHE.fromExternal(externalRecipient, inputProof);
        eaddress sender = FHE.fromExternal(externalSender, inputProof);
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);

        return confidentialTransferAndCallOmnibus(omnibusTo, sender, recipient, amount, data);
    }

    function confidentialTransferAndCallOmnibus(
        address omnibusTo,
        eaddress sender,
        eaddress recipient,
        euint64 amount,
        bytes calldata data
    ) public virtual returns (euint64) {
        FHE.allowThis(recipient);
        FHE.allow(recipient, omnibusTo);
        FHE.allow(recipient, msg.sender);

        FHE.allowThis(sender);
        FHE.allow(sender, omnibusTo);
        FHE.allow(sender, msg.sender);

        euint64 transferred = confidentialTransferAndCall(omnibusTo, amount, data);
        emit OmnibusConfidentialTransfer(msg.sender, omnibusTo, sender, recipient, transferred);
        return transferred;
    }

    function confidentialTransferFromAndCallOmnibus(
        address omnibusFrom,
        address omnibusTo,
        externalEaddress externalSender,
        externalEaddress externalRecipient,
        externalEuint64 externalAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public virtual returns (euint64) {
        eaddress recipient = FHE.fromExternal(externalRecipient, inputProof);
        eaddress sender = FHE.fromExternal(externalSender, inputProof);
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);

        return confidentialTransferFromAndCallOmnibus(omnibusFrom, omnibusTo, sender, recipient, amount, data);
    }

    function confidentialTransferFromAndCallOmnibus(
        address omnibusFrom,
        address omnibusTo,
        eaddress sender,
        eaddress recipient,
        euint64 amount,
        bytes calldata data
    ) public virtual returns (euint64) {
        FHE.allowThis(recipient);
        FHE.allow(recipient, omnibusTo);
        FHE.allow(recipient, omnibusFrom);

        FHE.allowThis(sender);
        FHE.allow(sender, omnibusTo);
        FHE.allow(sender, omnibusFrom);

        euint64 transferred = confidentialTransferFromAndCall(omnibusFrom, omnibusTo, amount, data);
        emit OmnibusConfidentialTransfer(omnibusFrom, omnibusTo, sender, recipient, transferred);
        return transferred;
    }
}
