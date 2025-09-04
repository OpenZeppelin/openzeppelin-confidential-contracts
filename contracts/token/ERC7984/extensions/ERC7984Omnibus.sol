// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, euint64, externalEuint64, externalEaddress, eaddress} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "../ERC7984.sol";

abstract contract ERC7984Omnibus is ERC7984 {
    event OmnibusTransfer(
        address indexed omnibusFrom,
        address indexed omnibusTo,
        eaddress indexed recipient,
        euint64 amount
    );

    function confidentialTransferOmnibus(
        address omnibusTo,
        externalEaddress recipient,
        externalEuint64 externalAmount,
        bytes calldata inputProof
    ) public returns (euint64) {
        eaddress recipient_ = FHE.fromExternal(recipient, inputProof);

        FHE.allowThis(recipient_);
        FHE.allow(recipient_, omnibusTo);
        FHE.allow(recipient_, msg.sender);

        euint64 transferred = confidentialTransfer(omnibusTo, externalAmount, inputProof);
        emit OmnibusTransfer(msg.sender, omnibusTo, recipient_, transferred);
        return transferred;
    }

    function confidentialTransferFromOmnibus(
        address omnibusFrom,
        address omnibusTo,
        externalEaddress recipient,
        externalEuint64 externalAmount,
        bytes calldata inputProof
    ) public returns (euint64) {
        eaddress recipient_ = FHE.fromExternal(recipient, inputProof);

        FHE.allowThis(recipient_);
        FHE.allow(recipient_, omnibusTo);
        FHE.allow(recipient_, omnibusFrom);

        euint64 transferred = confidentialTransferFrom(omnibusFrom, omnibusTo, externalAmount, inputProof);
        emit OmnibusTransfer(omnibusFrom, omnibusTo, recipient_, transferred);
        return transferred;
    }
}
