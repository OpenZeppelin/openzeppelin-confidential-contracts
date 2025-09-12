// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.2.0) (utils/FHESafeMath.sol)
pragma solidity ^0.8.24;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";

/**
 * @dev Library providing safe arithmetic operations for encrypted values
 * to handle potential overflows in FHE operations.
 */
library FHESafeMath {
    /**
     * @dev Try to increase the encrypted value `oldValue` by `delta`. If the operation is successful,
     * `success` will be true and `updated` will be the new value. Otherwise, `success` will be false
     * and `updated` will be the original value.
     */
    function tryIncrease(euint64 oldValue, euint64 delta) internal returns (ebool success, euint64 updated) {
        if (!FHE.isInitialized(oldValue)) {
            return (FHE.asEbool(true), delta);
        }
        euint64 newValue = FHE.add(oldValue, delta);
        success = FHE.ge(newValue, oldValue);
        updated = FHE.select(success, newValue, oldValue);
    }

    /**
     * @dev Try to decrease the encrypted value `oldValue` by `delta`. If the operation is successful,
     * `success` will be true and `updated` will be the new value. Otherwise, `success` will be false
     * and `updated` will be the original value.
     */
    function tryDecrease(euint64 oldValue, euint64 delta) internal returns (ebool success, euint64 updated) {
        if (!FHE.isInitialized(oldValue)) {
            if (!FHE.isInitialized(delta)) {
                return (FHE.asEbool(true), oldValue);
            }
            return (FHE.eq(oldValue, delta), oldValue);
        }
        success = FHE.ge(oldValue, delta);
        updated = FHE.select(success, FHE.sub(oldValue, delta), oldValue);
    }

    /**
     * @dev Try to add `a` and `b`. If the operation is successful, `success` will be true and `res`
     * will be the sum of `a` and `b`. Otherwise, `success` will be false, and `res` will be 0.
     */
    function tryAdd(euint64 a, euint64 b) internal returns (ebool success, euint64 res) {
        if (!FHE.isInitialized(a)) {
            return (FHE.asEbool(true), b);
        }
        if (!FHE.isInitialized(b)) {
            return (FHE.asEbool(true), a);
        }

        euint64 sum = FHE.add(a, b);
        success = FHE.ge(sum, a);
        res = FHE.select(success, sum, FHE.asEuint64(0));
    }

    /**
     * @dev Try to subtract `b` from `a`. If the operation is successful, `success` will be true and `res`
     * will be `a - b`. Otherwise, `success` will be false, and `res` will be 0.
     */
    function trySub(euint64 a, euint64 b) internal returns (ebool success, euint64 res) {
        if (!FHE.isInitialized(b)) {
            return (FHE.asEbool(true), a);
        }

        euint64 difference = FHE.sub(a, b);
        success = FHE.le(difference, a);
        res = FHE.select(success, difference, FHE.asEuint64(0));
    }
}
