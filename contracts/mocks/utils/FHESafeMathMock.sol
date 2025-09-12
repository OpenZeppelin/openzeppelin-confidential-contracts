// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {FHESafeMath} from "./../../utils/FHESafeMath.sol";

contract FHESafeMathMock is SepoliaConfig {
    event HandleCreated(euint64 amount);
    event ResultComputed(ebool success, euint64 updated);

    function createHandle(uint64 amount) public returns (euint64 handle) {
        handle = FHE.asEuint64(amount);
        FHE.allowThis(handle);
        FHE.allow(handle, msg.sender);
        emit HandleCreated(handle);
    }

    function tryIncrease(euint64 a, euint64 b) public returns (ebool success, euint64 updated) {
        (success, updated) = FHESafeMath.tryIncrease(a, b);
        FHE.allowThis(success);
        FHE.allow(success, msg.sender);

        if (FHE.isInitialized(updated)) {
            FHE.allowThis(updated);
            FHE.allow(updated, msg.sender);
        }

        emit ResultComputed(success, updated);
    }

    function tryDecrease(euint64 a, euint64 b) public returns (ebool success, euint64 updated) {
        (success, updated) = FHESafeMath.tryDecrease(a, b);
        FHE.allowThis(success);
        FHE.allow(success, msg.sender);

        if (FHE.isInitialized(updated)) {
            FHE.allowThis(updated);
            FHE.allow(updated, msg.sender);
        }

        emit ResultComputed(success, updated);
    }

    function tryAdd(euint64 a, euint64 b) public returns (ebool success, euint64 sum) {
        (success, sum) = FHESafeMath.tryAdd(a, b);
        FHE.allowThis(success);
        FHE.allow(success, msg.sender);

        if (FHE.isInitialized(sum)) {
            FHE.allowThis(sum);
            FHE.allow(sum, msg.sender);
        }

        emit ResultComputed(success, sum);
    }

    function trySub(euint64 a, euint64 b) public returns (ebool success, euint64 difference) {
        (success, difference) = FHESafeMath.trySub(a, b);
        FHE.allowThis(success);
        FHE.allow(success, msg.sender);

        if (FHE.isInitialized(difference)) {
            FHE.allowThis(difference);
            FHE.allow(difference, msg.sender);
        }

        emit ResultComputed(success, difference);
    }
}
