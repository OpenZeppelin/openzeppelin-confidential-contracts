// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";

library HandleHelper {
    function toExternal(euint64 encryptedAmount) internal pure returns (externalEuint64) {
        return externalEuint64.wrap(euint64.unwrap(encryptedAmount));
    }
}
