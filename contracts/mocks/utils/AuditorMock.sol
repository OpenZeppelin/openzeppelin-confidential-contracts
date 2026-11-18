// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {Auditor} from "./../../utils/Auditor.sol";

contract AuditorMock is Auditor, ZamaEthereumConfig {
    event HandleCreated(euint64 handle);

    function createHandle(uint64 amount) public returns (euint64 handle) {
        handle = FHE.asEuint64(amount);
        FHE.allowThis(handle);
        FHE.allow(handle, msg.sender);
        emit HandleCreated(handle);
    }
}
