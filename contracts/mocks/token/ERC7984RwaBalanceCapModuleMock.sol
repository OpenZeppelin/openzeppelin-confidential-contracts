// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984RwaBalanceCapModule} from "../../token/ERC7984/extensions/rwa/ERC7984RwaBalanceCapModule.sol";

contract ERC7984RwaBalanceCapModuleMock is ERC7984RwaBalanceCapModule, SepoliaConfig {
    event AmountEncrypted(euint64 amount);

    constructor(address compliance) ERC7984RwaBalanceCapModule(compliance) {}

    function createEncryptedAmount(uint64 amount) public returns (euint64 encryptedAmount) {
        FHE.allowThis(encryptedAmount = FHE.asEuint64(amount));
        FHE.allow(encryptedAmount, msg.sender);
        emit AmountEncrypted(encryptedAmount);
    }
}
