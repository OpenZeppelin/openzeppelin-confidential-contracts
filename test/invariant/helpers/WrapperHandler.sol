// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984ERC20WrapperMock} from "./../../../contracts/mocks/token/ERC7984/extensions/ERC7984ERC20WrapperMock.sol";
import {BaseHandler} from "./BaseHandler.sol";

/// @dev The handler is not a {FhevmTest}, so it cannot build the KMS public-decrypt proof
/// that {ERC7984ERC20Wrapper-finalizeUnwrap} requires. It delegates that to the invariant
/// test contract (which inherits FhevmTest) through this callback.
interface IUnwrapDecryptor {
    function finalizeArgs(bytes32 unwrapRequestId) external returns (uint64 cleartext, bytes memory proof);
}

/// @dev Managed handler for {ERC7984ERC20Wrapper} backing invariants (INV-W01..W04).
///
/// Routes every underlying and confidential flow so both the ERC-20 reserve and the
/// confidential supply stay attributable. Keeps a plaintext shadow ledger (in wrapper
/// units) plus ghost accumulators for pending unwraps, direct donations, and cumulative
/// underlying in/out. `unwrap` is bounded to the actor's shadow balance so the burn is
/// exact (burned == requested) and `fail_on_revert = true` holds.
contract WrapperHandler is BaseHandler {
    uint256 internal constant MAX_UNITS = type(uint64).max;

    ERC7984ERC20WrapperMock public immutable wrapper;
    IERC20 public immutable underlying;
    IUnwrapDecryptor public immutable decryptor;
    uint256 public immutable rate;

    // --- shadow ledger (plaintext mirror, wrapper units) ---
    mapping(address => uint256) public shadowBalanceUnits;
    uint256 public shadowSupplyUnits;

    // --- ghosts ---
    uint256 public ghostPendingUnwrap; // units burned via unwrap, not yet finalized
    uint256 public ghostDonated; // underlying transferred directly to the wrapper
    uint256 public ghostUnderlyingIn; // cumulative underlying pulled in by wrap
    uint256 public ghostUnderlyingOut; // cumulative underlying paid out by finalize

    // --- live unwrap requests ---
    bytes32[] internal _liveIds;
    mapping(bytes32 => uint256) public reqUnits;
    mapping(bytes32 => address) public reqTo;
    mapping(bytes32 => uint256) internal _reqIndex; // 1-based index into _liveIds (0 == absent)

    constructor(ERC7984ERC20WrapperMock wrapper_, IERC20 underlying_, IUnwrapDecryptor decryptor_) {
        wrapper = wrapper_;
        underlying = underlying_;
        decryptor = decryptor_;
        rate = wrapper_.rate();
        _addActor(address(0xA11CE));
        _addActor(address(0xB0B));
        _addActor(address(0xCA201));
        _addActor(address(0xD00D));
    }

    /// @dev inferredTotalSupply(): the wrapper's overflow guard reverts a mint when this
    /// exceeds uint64.max, so wraps/donations are bounded to keep it in range.
    function _inferredUnits() internal view returns (uint256) {
        return underlying.balanceOf(address(wrapper)) / rate;
    }

    /// @dev Wrap `mintedUnits * rate` underlying (plus sub-rate `dust` that gets refunded)
    /// from `from` to `to`.
    function wrap(uint256 fromSeed, uint256 toSeed, uint256 amount, uint256 dustSeed)
        external
        newBlock
        countCall("wrap")
    {
        address from = _rand(fromSeed);
        address to = _rand(toSeed);

        uint256 mintedUnits = bound(amount, 0, MAX_UNITS - _inferredUnits());
        uint256 dust = bound(dustSeed, 0, rate - 1); // exercise the refund path
        uint256 underlyingAmount = mintedUnits * rate + dust;

        deal(address(underlying), from, underlyingAmount);

        vm.startPrank(from);
        underlying.approve(address(wrapper), underlyingAmount);
        wrapper.wrap(to, underlyingAmount);
        vm.stopPrank();

        shadowBalanceUnits[to] += mintedUnits;
        shadowSupplyUnits += mintedUnits;
        ghostUnderlyingIn += mintedUnits * rate;
    }

    /// @dev Burn `units` from `from` (bounded to its balance so the burn is exact) and
    /// create an unwrap request paying underlying to `to`.
    function unwrap(uint256 fromSeed, uint256 toSeed, uint256 amount) external newBlock countCall("unwrap") {
        address from = _rand(fromSeed);
        address to = _rand(toSeed);
        uint256 units = bound(amount, 0, shadowBalanceUnits[from]);

        vm.startPrank(from);
        euint64 amt = wrapper.createEncryptedAmount(uint64(units));
        bytes32 id = wrapper.unwrap(from, to, amt);
        vm.stopPrank();

        shadowBalanceUnits[from] -= units;
        shadowSupplyUnits -= units;
        ghostPendingUnwrap += units;

        // Each newBlock yields a distinct ciphertext handle, so ids don't collide here.
        if (_reqIndex[id] == 0) {
            _liveIds.push(id);
            _reqIndex[id] = _liveIds.length;
        }
        reqUnits[id] = units;
        reqTo[id] = to;
    }

    /// @dev Finalize a live unwrap request: pull the KMS proof from the test contract, call
    /// finalizeUnwrap, and assert the one-shot / exact-payout properties of INV-W03.
    function finalize(uint256 seed) external newBlock countCall("finalize") {
        uint256 n = _liveIds.length;
        if (n == 0) return;
        uint256 idx = bound(seed, 0, n - 1);
        bytes32 id = _liveIds[idx];
        address to = reqTo[id];
        uint256 units = reqUnits[id];

        uint256 beforeBal = underlying.balanceOf(to);
        (uint64 cleartext, bytes memory proof) = decryptor.finalizeArgs(id);
        wrapper.finalizeUnwrap(id, cleartext, proof);
        uint256 afterBal = underlying.balanceOf(to);

        // INV-W03: finalize pays exactly units*rate to the recorded recipient and clears the request.
        require(uint256(cleartext) == units, "W03: cleartext != burned units");
        require(afterBal - beforeBal == units * rate, "W03: payout != units*rate");
        require(wrapper.unwrapRequester(id) == address(0), "W03: request not cleared");

        _removeReq(id, idx);
        ghostPendingUnwrap -= units;
        ghostUnderlyingOut += uint256(cleartext) * rate;
    }

    /// @dev Directly donate underlying to the wrapper (inflates inferredTotalSupply). Bounded
    /// so the overflow guard stays satisfied; fully accounted in ghostDonated for INV-W02.
    function donate(uint256 amount) external newBlock countCall("donate") {
        uint256 units = bound(amount, 0, MAX_UNITS - _inferredUnits());
        uint256 amt = units * rate;
        deal(address(underlying), address(wrapper), underlying.balanceOf(address(wrapper)) + amt);
        ghostDonated += amt;
    }

    function _removeReq(bytes32 id, uint256 idx) internal {
        uint256 last = _liveIds.length - 1;
        if (idx != last) {
            bytes32 moved = _liveIds[last];
            _liveIds[idx] = moved;
            _reqIndex[moved] = idx + 1;
        }
        _liveIds.pop();
        delete _reqIndex[id];
        delete reqUnits[id];
        delete reqTo[id];
    }

    // --- views consumed by the invariant contract ---
    function liveIdsLength() external view returns (uint256) {
        return _liveIds.length;
    }

    function liveIdAt(uint256 i) external view returns (bytes32) {
        return _liveIds[i];
    }
}
