// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.5.0) (utils/handleops/HandleOps.sol)
pragma solidity ^0.8.26;

import {ebool, euint64, externalEuint64} from "encrypted-types/EncryptedTypes.sol";

/**
 * @dev Abstract base that decouples the confidential contracts from any specific FHE backend.
 *
 * Implementation contracts (e.g. {ERC7984}) inherit this base and invoke the internal `_*`
 * operations instead of calling a concrete FHE library directly. A backend is selected by
 * inheriting a concrete implementation of these virtual functions (for example {ZamaHandleOps})
 * at the deployment/leaf contract.
 *
 * The encrypted value *types* (`euint64`, `ebool`, `externalEuint64`, ...) originate from the
 * `encrypted-types` package and are backend-agnostic; only the *operations* on handles are
 * abstracted here. This file intentionally does not import any FHE backend (e.g. the Zama fhEVM).
 *
 * The safe-arithmetic helpers (`_tryAdd`, `_trySub`, `_tryIncrease`, `_tryDecrease`,
 * `_saturatingAdd`, `_saturatingSub`) are concrete and implemented purely in terms of the virtual
 * primitives below, so they require no backend-specific code.
 */
abstract contract HandleOps {
    // ===================================================== ACL ======================================================

    /// @dev Grant persistent access to `value` to `account`.
    function _allow(euint64 value, address account) internal virtual;

    /// @dev Grant persistent access to `value` to the current contract.
    function _allowThis(euint64 value) internal virtual;

    /// @dev Grant transient (single-transaction) access to `value` to `account`.
    function _allowTransient(euint64 value, address account) internal virtual;

    /// @dev Whether `account` is allowed to access `value`.
    function _isAllowed(euint64 value, address account) internal view virtual returns (bool);

    /// @dev Whether `value` has been initialized (non-zero handle).
    function _isInitialized(euint64 value) internal view virtual returns (bool);

    /// @dev Grant persistent access to the raw handle `handle` to `account`.
    function _allowHandle(bytes32 handle, address account) internal virtual;

    /// @dev Grant transient access to the raw handle `handle` to `account`.
    function _allowTransientHandle(bytes32 handle, address account) internal virtual;

    // ================================================== Arithmetic ==================================================

    /// @dev Encrypted addition `a + b`.
    function _add(euint64 a, euint64 b) internal virtual returns (euint64);

    /// @dev Encrypted subtraction `a - b`.
    function _sub(euint64 a, euint64 b) internal virtual returns (euint64);

    /// @dev Encrypted minimum of `a` and `b`.
    function _min(euint64 a, euint64 b) internal virtual returns (euint64);

    // ================================================== Comparison ==================================================

    /// @dev Encrypted equality `a == b` against a cleartext `b`.
    function _eq(euint64 a, uint64 b) internal virtual returns (ebool);

    /// @dev Encrypted greater-or-equal `a >= b`.
    function _ge(euint64 a, euint64 b) internal virtual returns (ebool);

    /// @dev Encrypted less-or-equal `a <= b`.
    function _le(euint64 a, euint64 b) internal virtual returns (ebool);

    // =================================================== Control ====================================================

    /// @dev Encrypted ternary: returns `a` if `control` is true, otherwise `b`.
    function _select(ebool control, euint64 a, euint64 b) internal virtual returns (euint64);

    // ============================================== Conversion / input ==============================================

    /// @dev Trivially encrypt the cleartext `value`.
    function _asEuint64(uint64 value) internal virtual returns (euint64);

    /// @dev Trivially encrypt the cleartext boolean `value`.
    function _asEbool(bool value) internal virtual returns (ebool);

    /// @dev Validate and import an externally-provided ciphertext.
    function _fromExternal(externalEuint64 inputHandle, bytes memory inputProof) internal virtual returns (euint64);

    // ================================================== Disclosure ==================================================

    /// @dev Request that `value` be made publicly decryptable.
    function _makePubliclyDecryptable(euint64 value) internal virtual;

    /// @dev Verify decryption-oracle signatures over `handles`/`cleartexts`.
    function _checkSignatures(
        bytes32[] memory handles,
        bytes memory cleartexts,
        bytes memory decryptionProof
    ) internal virtual;

    // ============================================== Safe arithmetic =================================================

    /**
     * @dev Try to increase the encrypted value `oldValue` by `delta`. If the operation is successful,
     * `success` will be true and `updated` will be the new value. Otherwise, `success` will be false
     * and `updated` will be the original value.
     *
     * NOTE: An uninitialized `euint64` value (equivalent to `euint64.wrap(bytes32(0))`) is evaluated as 0.
     * This may return an uninitialized value if all inputs are uninitialized.
     */
    function _tryIncrease(euint64 oldValue, euint64 delta) internal returns (ebool success, euint64 updated) {
        if (!_isInitialized(oldValue)) {
            return (_asEbool(true), delta);
        }
        euint64 newValue = _add(oldValue, delta);
        success = _ge(newValue, oldValue);
        updated = _select(success, newValue, oldValue);
    }

    /**
     * @dev Try to decrease the encrypted value `oldValue` by `delta`. If the operation is successful,
     * `success` will be true and `updated` will be the new value. Otherwise, `success` will be false
     * and `updated` will be the original value.
     */
    function _tryDecrease(euint64 oldValue, euint64 delta) internal returns (ebool success, euint64 updated) {
        if (!_isInitialized(oldValue)) {
            if (!_isInitialized(delta)) {
                return (_asEbool(true), oldValue);
            }
            return (_eq(delta, 0), _asEuint64(0));
        }
        success = _ge(oldValue, delta);
        updated = _select(success, _sub(oldValue, delta), oldValue);
    }

    /**
     * @dev Try to add `a` and `b`. If the operation is successful, `success` will be true and `res`
     * will be the sum of `a` and `b`. Otherwise, `success` will be false, and `res` will be 0.
     */
    function _tryAdd(euint64 a, euint64 b) internal returns (ebool success, euint64 res) {
        if (!_isInitialized(a)) {
            return (_asEbool(true), b);
        }
        if (!_isInitialized(b)) {
            return (_asEbool(true), a);
        }

        euint64 sum = _add(a, b);
        success = _ge(sum, a);
        res = _select(success, sum, _asEuint64(0));
    }

    /**
     * @dev Try to subtract `b` from `a`. If the operation is successful, `success` will be true and `res`
     * will be `a - b`. Otherwise, `success` will be false, and `res` will be 0.
     */
    function _trySub(euint64 a, euint64 b) internal returns (ebool success, euint64 res) {
        if (!_isInitialized(b)) {
            return (_asEbool(true), a);
        }

        euint64 difference = _sub(a, b);
        success = _le(difference, a);
        res = _select(success, difference, _asEuint64(0));
    }

    /**
     * @dev Add `a` and `b` saturating at `type(uint64).max` on overflow. The returned value is the sum
     * of `a` and `b` if it does not overflow, otherwise `type(uint64).max`.
     */
    function _saturatingAdd(euint64 a, euint64 b) internal returns (euint64) {
        if (!_isInitialized(a)) {
            return b;
        }
        if (!_isInitialized(b)) {
            return a;
        }

        euint64 sum = _add(a, b);
        return _select(_ge(sum, a), sum, _asEuint64(type(uint64).max));
    }

    /**
     * @dev Subtract `b` from `a` saturating at zero on underflow. The returned value is `a - b` if
     * `a >= b`, otherwise 0.
     */
    function _saturatingSub(euint64 a, euint64 b) internal returns (euint64) {
        euint64 minB = _min(a, b);
        return _sub(a, minB);
    }
}
