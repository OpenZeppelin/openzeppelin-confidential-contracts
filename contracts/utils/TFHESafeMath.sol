// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TFHE, ebool, euint64 } from "fhevm/lib/TFHE.sol";

/**
 * @dev Library providing safe arithmetic operations for encrypted values
 * to handle potential overflows in FHE operations.
 */
library TFHESafeMath {
    /**
     * @dev Try to increase the encrypted value `oldValue` by `delta`. If the operation is successful,
     * `success` will be true and `updated` will be the new value. Otherwise, `success` will be false
     * and `updated` will be the original value.
     */
    function tryIncrease(euint64 oldValue, euint64 delta) internal returns (ebool success, euint64 updated) {
        if (euint64.unwrap(oldValue) == 0) {
            success = TFHE.asEbool(true);
            updated = delta;
        } else {
            euint64 newValue = TFHE.add(oldValue, delta);
            success = TFHE.ge(newValue, oldValue);
            updated = TFHE.select(success, newValue, oldValue);
        }
    }

    /**
     * @dev Try to decrease the encrypted value `oldValue` by `delta`. If the operation is successful,
     * `success` will be true and `updated` will be the new value. Otherwise, `success` will be false
     * and `updated` will be the original value.
     */
    function tryDecrease(euint64 oldValue, euint64 delta) internal returns (ebool success, euint64 updated) {
        success = TFHE.ge(oldValue, delta);
        updated = TFHE.select(success, TFHE.sub(oldValue, delta), oldValue);
    }
}
