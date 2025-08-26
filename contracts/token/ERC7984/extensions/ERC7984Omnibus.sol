// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, euint64, externalEuint64, eaddress} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "../ERC7984.sol";

abstract contract ERC7984Omnibus is ERC7984 {
    event OmnibusTransfer(
        address indexed omnibusFrom,
        address indexed omnibusTo,
        eaddress indexed sender,
        eaddress recipient,
        euint64 amount
    );

    function confidentialTransferFromOmnibus(
        address omnibusFrom,
        address omnibusTo,
        eaddress sender,
        eaddress recipient,
        externalEuint64 externalAmount,
        bytes calldata inputProof
    ) public returns (euint64) {
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);
        emit OmnibusTransfer(omnibusFrom, omnibusTo, sender, recipient, amount);
        return confidentialTransferFrom(omnibusFrom, omnibusTo, amount);
    }

    function confidentialTransferFromOmnibus(
        address omnibusFrom,
        address omnibusTo,
        eaddress sender,
        eaddress recipient,
        euint64 amount
    ) public returns (euint64) {
        emit OmnibusTransfer(omnibusFrom, omnibusTo, sender, recipient, amount);
        return confidentialTransferFrom(omnibusFrom, omnibusTo, amount);
    }
}
