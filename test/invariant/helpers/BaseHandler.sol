// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {AddressSet, LibAddressSet} from "./AddressSet.sol";

/// @dev Base handler for managed (handler-based) invariant testing.
///
/// A handler wraps the target contract and is the ONLY thing the fuzzer calls. It:
///   - bounds inputs (via StdUtils.bound) so calls stay in valid, non-reverting ranges,
///   - restricts msg.sender to a known actor set (`useActor`), and
///   - records call distribution (`countCall`) so `invariant-run` can prove the suite
///     actually exercised each entry point.
///
/// Concrete handlers inherit this, add per-function wrappers, and maintain ghost
/// variables. Update ghosts ONLY after the wrapped call succeeds.
abstract contract BaseHandler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    AddressSet internal _actors;
    address internal currentActor;

    /// @dev call name => number of times invoked (for coverage reporting).
    mapping(bytes32 => uint256) public calls;

    /// @dev Seed the actor set. Call from the handler constructor.
    function _addActor(address actor) internal {
        _actors.add(actor);
    }

    /// @dev Pick an actor deterministically from the seed and prank as them for the
    /// duration of the wrapped call. If the set is empty, create+register a fresh one.
    modifier useActor(uint256 actorSeed) {
        currentActor = _actors.rand(actorSeed);
        if (currentActor == address(0)) {
            currentActor = address(uint160(uint256(keccak256(abi.encode("actor", actorSeed)))));
            _actors.add(currentActor);
        }
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @dev Record a call for the coverage histogram.
    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    /// @dev Advance to a fresh block before the wrapped call. Under forge-fhevm the mock
    /// host enforces a per-block HCU (homomorphic complexity) budget that resets when
    /// `block.number` changes; without this, a long invariant sequence of FHE-heavy ops
    /// exhausts one block's budget and reverts `HCUBlockLimitExceeded()`. In production
    /// each such op is its own transaction/block, so one-block-per-call is the faithful
    /// model, not a workaround that hides contract behavior.
    modifier newBlock() {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 12);
        _;
    }

    // --- views consumed by the invariant test contract -------------------------------

    function actors() external view returns (address[] memory) {
        return _actors.addrs;
    }

    function actorCount() external view returns (uint256) {
        return _actors.count();
    }

    function callCount(bytes32 key) external view returns (uint256) {
        return calls[key];
    }

    /// @dev Emit the call histogram to the console at the end of a run for the
    /// `invariant-run` skill to scrape. Override `_callKeys()` in the concrete handler.
    function callSummary() external view virtual {}
}
