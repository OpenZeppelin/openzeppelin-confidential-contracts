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
     * `omnibusFrom` and `omnibusTo` and is represented in a matching {IERC7984-ConfidentialTransfer} event.
     *
     * NOTE: `omnibusFrom` and `omnibusTo` get permanent ACL allowances for `sender` and `recipient`.
     */
    event OmnibusConfidentialTransfer(
        address indexed omnibusFrom,
        address indexed omnibusTo,
        eaddress sender,
        eaddress indexed recipient,
        euint64 amount
    );

    /**
     * @dev The caller `user` does not have access to the encrypted address `addr`.
     *
     * NOTE: Try using the equivalent transfer function with an input proof.
     */
    error ERC7984UnauthorizedUseOfEncryptedAddress(eaddress addr);

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

        return confidentialTransferFromOmnibus(msg.sender, omnibusTo, sender, recipient, amount);
    }

    function confidentialTransferOmnibus(
        address omnibusTo,
        eaddress sender,
        eaddress recipient,
        euint64 amount
    ) public virtual returns (euint64) {
        return confidentialTransferFromOmnibus(msg.sender, omnibusTo, sender, recipient, amount);
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
        require(FHE.isAllowed(sender, msg.sender), ERC7984UnauthorizedUseOfEncryptedAddress(sender));
        require(FHE.isAllowed(recipient, msg.sender), ERC7984UnauthorizedUseOfEncryptedAddress(recipient));

        FHE.allowThis(sender);
        FHE.allow(sender, omnibusFrom);
        FHE.allow(sender, omnibusTo);

        FHE.allowThis(recipient);
        FHE.allow(recipient, omnibusFrom);
        FHE.allow(recipient, omnibusTo);

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
        eaddress sender = FHE.fromExternal(externalSender, inputProof);
        eaddress recipient = FHE.fromExternal(externalRecipient, inputProof);
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);

        return confidentialTransferFromAndCallOmnibus(msg.sender, omnibusTo, sender, recipient, amount, data);
    }

    function confidentialTransferAndCallOmnibus(
        address omnibusTo,
        eaddress sender,
        eaddress recipient,
        euint64 amount,
        bytes calldata data
    ) public virtual returns (euint64) {
        return confidentialTransferFromAndCallOmnibus(msg.sender, omnibusTo, sender, recipient, amount, data);
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
        eaddress sender = FHE.fromExternal(externalSender, inputProof);
        eaddress recipient = FHE.fromExternal(externalRecipient, inputProof);
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
        require(FHE.isAllowed(sender, msg.sender), ERC7984UnauthorizedUseOfEncryptedAddress(sender));
        require(FHE.isAllowed(recipient, msg.sender), ERC7984UnauthorizedUseOfEncryptedAddress(recipient));

        euint64 transferred = confidentialTransferFromAndCall(omnibusFrom, omnibusTo, amount, data);

        FHE.allowThis(sender);
        FHE.allow(sender, omnibusFrom);
        FHE.allow(sender, omnibusTo);

        FHE.allowThis(recipient);
        FHE.allow(recipient, omnibusFrom);
        FHE.allow(recipient, omnibusTo);

        FHE.allowThis(transferred);
        FHE.allow(transferred, omnibusFrom);
        FHE.allow(transferred, omnibusTo);

        emit OmnibusConfidentialTransfer(omnibusFrom, omnibusTo, sender, recipient, transferred);
        return transferred;
    }
}
