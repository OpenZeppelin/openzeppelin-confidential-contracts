// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, eaddress, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984Omnibus} from "../../../../token/ERC7984/extensions/ERC7984Omnibus.sol";
import {HandleHelper} from "../../../../utils/HandleHelper.sol";

/// @dev Omnibus account contract that forwards tokens using handles it creates, passed with an empty input proof.
contract ERC7984OmnibusForwarderMock is ZamaEthereumConfig {
    using HandleHelper for euint64;
    using HandleHelper for eaddress;

    function forward(
        ERC7984Omnibus token,
        address omnibusTo,
        address sender,
        address recipient,
        uint64 amount
    ) public returns (euint64) {
        eaddress encryptedSender = FHE.asEaddress(sender);
        eaddress encryptedRecipient = FHE.asEaddress(recipient);
        euint64 encryptedAmount = FHE.asEuint64(amount);

        FHE.allowTransient(encryptedSender, address(token));
        FHE.allowTransient(encryptedRecipient, address(token));
        FHE.allowTransient(encryptedAmount, address(token));

        return
            token.confidentialTransferOmnibus(
                omnibusTo,
                encryptedSender.toExternal(),
                encryptedRecipient.toExternal(),
                encryptedAmount.toExternal(),
                hex""
            );
    }
}
