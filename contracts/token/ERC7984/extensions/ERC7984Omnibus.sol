// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, euint64, externalEuint64, externalEaddress, eaddress} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "../ERC7984.sol";

abstract contract ERC7984Omnibus is ERC7984 {
    event OmnibusTransfer(
        address indexed omnibusFrom,
        address indexed omnibusTo,
        eaddress sender,
        eaddress indexed recipient,
        euint64 amount
    );

    function confidentialTransferOmnibus(
        address omnibusTo,
        externalEaddress sender,
        externalEaddress recipient,
        externalEuint64 externalAmount,
        bytes calldata inputProof
    ) public returns (euint64) {
        eaddress recipient_ = FHE.fromExternal(recipient, inputProof);
        eaddress sender_ = FHE.fromExternal(sender, inputProof);

        FHE.allowThis(recipient_);
        FHE.allow(recipient_, omnibusTo);
        FHE.allow(recipient_, msg.sender);

        FHE.allowThis(sender_);
        FHE.allow(sender_, omnibusTo);
        FHE.allow(sender_, msg.sender);

        euint64 transferred = confidentialTransfer(omnibusTo, externalAmount, inputProof);
        emit OmnibusTransfer(msg.sender, omnibusTo, sender_, recipient_, transferred);
        return transferred;
    }

    function confidentialTransferFromOmnibus(
        address omnibusFrom,
        address omnibusTo,
        externalEaddress sender,
        externalEaddress recipient,
        externalEuint64 externalAmount,
        bytes calldata inputProof
    ) public returns (euint64) {
        eaddress recipient_ = FHE.fromExternal(recipient, inputProof);
        eaddress sender_ = FHE.fromExternal(sender, inputProof);

        FHE.allowThis(recipient_);
        FHE.allow(recipient_, omnibusTo);
        FHE.allow(recipient_, omnibusFrom);

        FHE.allowThis(sender_);
        FHE.allow(sender_, omnibusTo);
        FHE.allow(sender_, omnibusFrom);

        euint64 transferred = confidentialTransferFrom(omnibusFrom, omnibusTo, externalAmount, inputProof);
        emit OmnibusTransfer(omnibusFrom, omnibusTo, sender_, recipient_, transferred);
        return transferred;
    }
}
