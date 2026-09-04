// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC7984Mock} from "./../../../contracts/mocks/token/ERC7984/ERC7984Mock.sol";
import {AddressSet, LibAddressSet} from "./AddressSet.sol";
import {BaseHandler} from "./BaseHandler.sol";

/// @dev Managed handler for {ERC7984} accounting invariants.
///
/// Every value movement is routed through here so no balance escapes the actor set.
/// Because {FHESafeMath} makes mint/burn/transfer all-or-nothing and revert-free, the
/// handler keeps an exact plaintext SHADOW ledger that mirrors the encrypted state. The
/// invariant contract decrypts the real handles and compares them to this shadow, so the
/// shadow doubles as the ghost model for INV-02/INV-03.
contract ERC7984Handler is BaseHandler {
    using LibAddressSet for AddressSet;

    uint64 internal constant MAX = type(uint64).max;

    ERC7984Mock public immutable token;

    // --- shadow model (plaintext mirror of encrypted accounting) ---
    mapping(address => uint256) public shadowBalance;
    uint256 public shadowSupply;
    uint256 public ghostMinted;
    uint256 public ghostBurned;

    constructor(ERC7984Mock token_) {
        token = token_;
        // Fixed, small actor set keeps the balance sum bounded and coverage focused.
        _addActor(address(0xA11CE));
        _addActor(address(0xB0B));
        _addActor(address(0xCA201));
        _addActor(address(0xD00D));
    }

    /// @dev Mint over the FULL uint64 range so the aggregate-supply overflow branch of
    /// `tryIncrease` is reachable. On overflow the real op is a no-op (transferred == 0);
    /// the shadow models exactly that.
    function mint(uint256 toSeed, uint256 amount) external newBlock countCall("mint") {
        address to = _actors.rand(toSeed);
        amount = bound(amount, 0, MAX);

        token.$_mint(to, uint64(amount));

        if (shadowSupply + amount <= MAX) {
            shadowSupply += amount;
            shadowBalance[to] += amount;
            ghostMinted += amount;
        }
        // else: tryIncrease rejected -> supply and balance unchanged.
    }

    /// @dev Burn a sender-affordable amount so the success path is exercised and the
    /// shadow stays exact. (The insufficient-balance no-op branch is covered by INV-04.)
    function burn(uint256 fromSeed, uint256 amount) external newBlock countCall("burn") {
        address from = _actors.rand(fromSeed);
        amount = bound(amount, 0, shadowBalance[from]);

        token.$_burn(from, uint64(amount));

        shadowBalance[from] -= amount;
        shadowSupply -= amount;
        ghostBurned += amount;
    }

    /// @dev Transfer a sender-affordable amount between actors.
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external newBlock countCall("transfer") {
        address from = _actors.rand(fromSeed);
        address to = _actors.rand(toSeed);
        amount = bound(amount, 0, shadowBalance[from]);

        vm.prank(from);
        token.confidentialTransfer(to, uint64(amount));

        // from == to is a net-zero move; the arithmetic below handles it correctly.
        shadowBalance[from] -= amount;
        shadowBalance[to] += amount;
    }
}
