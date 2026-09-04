// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {FHESafeMathMock} from "./../../../contracts/mocks/utils/FHESafeMathMock.sol";
import {BaseHandler} from "./BaseHandler.sol";

/// @dev Managed handler for {FHESafeMath} correctness (INV-04).
///
/// Maintains a running encrypted accumulator `acc` driven through `tryIncrease` /
/// `tryDecrease` — the exact operations {ERC7984-_update} relies on — alongside a
/// plaintext `shadowAcc` computed with the library's documented semantics. It also
/// spot-checks the stateless `tryAdd` / `trySub` ops on fresh inputs. The invariant
/// contract decrypts the handles and compares against the model.
contract SafeMathHandler is BaseHandler {
    uint64 internal constant MAX = type(uint64).max;

    FHESafeMathMock public immutable math;

    // --- accumulator chain (tryIncrease / tryDecrease) ---
    euint64 public acc;
    uint256 public shadowAcc;
    bool public accInit;
    ebool public lastSuccess;
    bool public expectedSuccess;
    bool public hasOp;

    // --- fresh binary ops (tryAdd / trySub) ---
    euint64 public lastFreshRes;
    uint256 public lastFreshExpected;
    ebool public freshSuccess;
    bool public freshSuccessExpected;
    bool public hasFresh;

    constructor(FHESafeMathMock math_) {
        math = math_;
    }

    function increase(uint256 x) external newBlock countCall("increase") {
        x = bound(x, 0, MAX);
        (ebool s, euint64 u) = math.tryIncrease(acc, math.createHandle(uint64(x)));
        acc = u;
        lastSuccess = s;
        hasOp = true;

        if (!accInit) {
            // Uninitialized oldValue: tryIncrease returns (true, delta).
            accInit = true;
            shadowAcc = x;
            expectedSuccess = true;
        } else if (shadowAcc + x <= MAX) {
            shadowAcc += x;
            expectedSuccess = true;
        } else {
            expectedSuccess = false; // overflow -> value unchanged
        }
    }

    function decrease(uint256 x) external newBlock countCall("decrease") {
        x = bound(x, 0, MAX);
        (ebool s, euint64 u) = math.tryDecrease(acc, math.createHandle(uint64(x)));
        acc = u;
        lastSuccess = s;
        hasOp = true;

        if (!accInit) {
            // Uninitialized oldValue, initialized delta: returns (eq(delta,0), 0).
            accInit = true;
            shadowAcc = 0;
            expectedSuccess = (x == 0);
        } else if (shadowAcc >= x) {
            shadowAcc -= x;
            expectedSuccess = true;
        } else {
            expectedSuccess = false; // underflow -> value unchanged
        }
    }

    function addFresh(uint256 x, uint256 y) external newBlock countCall("addFresh") {
        x = bound(x, 0, MAX);
        y = bound(y, 0, MAX);
        (ebool s, euint64 res) = math.tryAdd(math.createHandle(uint64(x)), math.createHandle(uint64(y)));
        lastFreshRes = res;
        freshSuccess = s;
        hasFresh = true;

        bool ok = (x + y <= MAX);
        freshSuccessExpected = ok;
        lastFreshExpected = ok ? (x + y) : 0;
    }

    function subFresh(uint256 x, uint256 y) external newBlock countCall("subFresh") {
        x = bound(x, 0, MAX);
        y = bound(y, 0, MAX);
        (ebool s, euint64 res) = math.trySub(math.createHandle(uint64(x)), math.createHandle(uint64(y)));
        lastFreshRes = res;
        freshSuccess = s;
        hasFresh = true;

        bool ok = (x >= y);
        freshSuccessExpected = ok;
        lastFreshExpected = ok ? (x - y) : 0;
    }
}
