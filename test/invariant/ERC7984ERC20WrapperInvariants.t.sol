// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "../../contracts/mocks/token/ERC20Mock.sol";
import {ERC7984ERC20WrapperMock} from "../../contracts/mocks/token/ERC7984/extensions/ERC7984ERC20WrapperMock.sol";
import {WrapperHandler, IUnwrapDecryptor} from "./helpers/WrapperHandler.sol";

/// @dev Invariants INV-W01..W04 from invariants.md — ERC7984ERC20Wrapper backing.
///
/// The wrapper custodies a plain ERC-20 (`underlying`) and mints confidential tokens against
/// it at a fixed `rate`. These invariants check that the reserve always backs everything
/// outstanding (supply + burned-but-unfinalized unwraps), that the accounting is exact once
/// donations are removed, and that rounding never leaks value.
///
/// FHE runs under forge-fhevm: encrypted supply is read with `decrypt(...)`, and the KMS
/// proof that `finalizeUnwrap` needs is built here via `publicDecrypt(...)` and handed to the
/// handler through the {IUnwrapDecryptor} callback (the handler is not a FhevmTest itself).
contract ERC7984ERC20WrapperInvariants is FhevmTest, IUnwrapDecryptor {
    ERC20Mock internal underlying;
    ERC7984ERC20WrapperMock internal wrapper;
    WrapperHandler internal handler;
    uint256 internal rate;

    function setUp() public override {
        super.setUp(); // deploy FHE host, start log recording
        disableHCUDepthLimit(); // invariant sequences chain many FHE ops per run

        // 9-decimal underlying -> rate = 10**(9 - maxDecimals(6)) = 1000, so wrap rounding and
        // the excess-refund path are actually exercised (rate == 1 would hide them).
        underlying = new ERC20Mock("Underlying", "UND", 9);
        wrapper = new ERC7984ERC20WrapperMock(IERC20(address(underlying)), "Wrapped", "WND", "");
        rate = wrapper.rate();

        handler = new WrapperHandler(wrapper, IERC20(address(underlying)), IUnwrapDecryptor(address(this)));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = WrapperHandler.wrap.selector;
        selectors[1] = WrapperHandler.unwrap.selector;
        selectors[2] = WrapperHandler.finalize.selector;
        selectors[3] = WrapperHandler.donate.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev Decryptor callback (see {IUnwrapDecryptor}): build the public-decrypt cleartext +
    /// KMS proof for `id`, which `_unwrap` marked publicly decryptable.
    function finalizeArgs(bytes32 id) external returns (uint64 cleartext, bytes memory proof) {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = id;
        (uint256[] memory cleartexts, bytes memory p) = publicDecrypt(handles);
        return (uint64(cleartexts[0]), p);
    }

    /// INV-W01: underlying reserve always covers supply + pending unwraps (tolerates donations).
    function invariant_INVW01_reserveSolvency() public {
        uint256 required = (decrypt(wrapper.confidentialTotalSupply()) + handler.ghostPendingUnwrap()) * rate;
        assertGe(underlying.balanceOf(address(wrapper)), required, "reserve < supply + pending");
    }

    /// INV-W02: exact backing — reserve == (supply + pending)*rate + donations. Sharp version.
    function invariant_INVW02_exactBacking() public {
        uint256 supply = decrypt(wrapper.confidentialTotalSupply());
        assertEq(supply, handler.shadowSupplyUnits(), "supply != shadow");
        uint256 expected = (supply + handler.ghostPendingUnwrap()) * rate + handler.ghostDonated();
        assertEq(underlying.balanceOf(address(wrapper)), expected, "reserve != exact backing");
    }

    /// INV-W03: pending set is well-formed — every live request has the recorded recipient and
    /// the live amounts sum to the tracked pending total. (Exact payout + one-shot finalize are
    /// asserted atomically in the handler's finalize.)
    function invariant_INVW03_pendingWellFormed() public {
        uint256 n = handler.liveIdsLength();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            bytes32 id = handler.liveIdAt(i);
            address requester = wrapper.unwrapRequester(id);
            assertTrue(requester != address(0), "live request has no recipient");
            assertEq(requester, handler.reqTo(id), "recipient mismatch");
            sum += handler.reqUnits(id);
        }
        assertEq(sum, handler.ghostPendingUnwrap(), "live amounts != pending total");
    }

    /// INV-W04: cumulative underlying paid out never exceeds cumulative underlying wrapped in.
    function invariant_INVW04_noFreeValue() public view {
        assertLe(handler.ghostUnderlyingOut(), handler.ghostUnderlyingIn(), "payouts > deposits");
    }
}
