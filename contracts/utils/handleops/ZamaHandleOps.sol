// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.5.0) (utils/handleops/ZamaHandleOps.sol)
pragma solidity ^0.8.26;

import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {Impl} from "@fhevm/solidity/lib/Impl.sol";
import {HandleOps} from "./HandleOps.sol";

/**
 * @dev {HandleOps} implementation backed by Zama's fhEVM (the `fhevm/solidity` library).
 *
 * This is the reference handle-ops backend. Inherit it at a concrete/leaf contract (alongside a
 * Zama config such as `ZamaEthereumConfig`) to make a {HandleOps}-based contract deployable on the
 * Zama coprocessor. It is the only contract in the abstracted path that depends on the Zama library.
 */
abstract contract ZamaHandleOps is HandleOps {
    // ===================================================== ACL ======================================================

    function _allow(euint64 value, address account) internal override {
        FHE.allow(value, account);
    }

    function _allowThis(euint64 value) internal override {
        FHE.allowThis(value);
    }

    function _allowTransient(euint64 value, address account) internal override {
        FHE.allowTransient(value, account);
    }

    function _isAllowed(euint64 value, address account) internal view override returns (bool) {
        return FHE.isAllowed(value, account);
    }

    function _isInitialized(euint64 value) internal pure override returns (bool) {
        return FHE.isInitialized(value);
    }

    function _allowHandle(bytes32 handle, address account) internal override {
        Impl.allow(handle, account);
    }

    function _allowTransientHandle(bytes32 handle, address account) internal override {
        Impl.allowTransient(handle, account);
    }

    // ================================================== Arithmetic ==================================================

    function _add(euint64 a, euint64 b) internal override returns (euint64) {
        return FHE.add(a, b);
    }

    function _sub(euint64 a, euint64 b) internal override returns (euint64) {
        return FHE.sub(a, b);
    }

    function _min(euint64 a, euint64 b) internal override returns (euint64) {
        return FHE.min(a, b);
    }

    // ================================================== Comparison ==================================================

    function _eq(euint64 a, uint64 b) internal override returns (ebool) {
        return FHE.eq(a, b);
    }

    function _ge(euint64 a, euint64 b) internal override returns (ebool) {
        return FHE.ge(a, b);
    }

    function _le(euint64 a, euint64 b) internal override returns (ebool) {
        return FHE.le(a, b);
    }

    // =================================================== Control ====================================================

    function _select(ebool control, euint64 a, euint64 b) internal override returns (euint64) {
        return FHE.select(control, a, b);
    }

    // ============================================== Conversion / input ==============================================

    function _asEuint64(uint64 value) internal override returns (euint64) {
        return FHE.asEuint64(value);
    }

    function _asEbool(bool value) internal override returns (ebool) {
        return FHE.asEbool(value);
    }

    function _fromExternal(
        externalEuint64 inputHandle,
        bytes memory inputProof
    ) internal override returns (euint64) {
        return FHE.fromExternal(inputHandle, inputProof);
    }

    // ================================================== Disclosure ==================================================

    function _makePubliclyDecryptable(euint64 value) internal override {
        FHE.makePubliclyDecryptable(value);
    }

    function _checkSignatures(
        bytes32[] memory handles,
        bytes memory cleartexts,
        bytes memory decryptionProof
    ) internal override {
        FHE.checkSignatures(handles, cleartexts, decryptionProof);
    }
}
