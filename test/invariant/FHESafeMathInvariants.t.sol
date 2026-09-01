// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {FHESafeMathMock} from "../../contracts/mocks/utils/FHESafeMathMock.sol";
import {SafeMathHandler} from "./helpers/SafeMathHandler.sol";

/// @dev Invariant INV-04 from invariants.md — FHESafeMath try-ops match the plaintext model.
contract FHESafeMathInvariants is FhevmTest {
    FHESafeMathMock internal math;
    SafeMathHandler internal handler;

    function setUp() public override {
        super.setUp();
        disableHCUDepthLimit();

        math = new FHESafeMathMock();
        handler = new SafeMathHandler(math);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = SafeMathHandler.increase.selector;
        selectors[1] = SafeMathHandler.decrease.selector;
        selectors[2] = SafeMathHandler.addFresh.selector;
        selectors[3] = SafeMathHandler.subFresh.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// INV-04: the tryIncrease/tryDecrease accumulator and the tryAdd/trySub fresh ops
    /// always match the reference plaintext computation (value AND success flag).
    function invariant_INV04_safeMathMatchesModel() public {
        if (handler.hasOp()) {
            assertEq(uint256(decrypt(handler.acc())), handler.shadowAcc(), "acc != shadow");
            assertEq(decrypt(handler.lastSuccess()), handler.expectedSuccess(), "success flag mismatch");
        }
        if (handler.hasFresh()) {
            assertEq(uint256(decrypt(handler.lastFreshRes())), handler.lastFreshExpected(), "fresh res mismatch");
            assertEq(decrypt(handler.freshSuccess()), handler.freshSuccessExpected(), "fresh success mismatch");
        }
    }
}
