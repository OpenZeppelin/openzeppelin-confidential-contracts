// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {ERC7984Mock} from "../../contracts/mocks/token/ERC7984/ERC7984Mock.sol";
import {ERC7984Handler} from "./helpers/ERC7984Handler.sol";

/// @dev Invariants INV-01..INV-03 from invariants.md — ERC7984 confidential accounting.
///
/// FHE runs under forge-fhevm: `setUp()` stands up the mock host, and encrypted handles
/// are read back with `decrypt(...)`, which resolves against the plaintext DB the mixin
/// rebuilds from FHE event logs (no ACL required to decrypt).
contract ERC7984Invariants is FhevmTest {
    ERC7984Mock internal token;
    ERC7984Handler internal handler;

    function setUp() public override {
        super.setUp(); // deploy FHE host, start log recording
        disableHCUDepthLimit(); // invariant sequences chain many FHE ops per run

        token = new ERC7984Mock("Confidential", "CTKN", "");
        handler = new ERC7984Handler(token);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = ERC7984Handler.mint.selector;
        selectors[1] = ERC7984Handler.burn.selector;
        selectors[2] = ERC7984Handler.transfer.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// INV-01: confidentialTotalSupply == Σ confidentialBalanceOf(actor).
    function invariant_supplyEqualsSumOfBalances() public {
        address[] memory actors = handler.actors();
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += decrypt(token.confidentialBalanceOf(actors[i]));
        }
        assertEq(uint256(decrypt(token.confidentialTotalSupply())), sum, "supply != sum of balances");
    }

    /// INV-02: supply == net minted, cross-checked against the shadow model.
    function invariant_supplyEqualsNetMinted() public {
        uint256 supply = decrypt(token.confidentialTotalSupply());
        assertEq(supply, handler.shadowSupply(), "supply != shadow supply");
        assertEq(supply, handler.ghostMinted() - handler.ghostBurned(), "supply != minted - burned");
    }

    /// INV-03: no balance exceeds supply (underflow/overflow-wrap detector), and each
    /// balance equals its shadow (so an overflowing mint stayed a no-op).
    function invariant_noBalanceExceedsSupply() public {
        uint256 supply = decrypt(token.confidentialTotalSupply());
        address[] memory actors = handler.actors();
        for (uint256 i; i < actors.length; ++i) {
            uint256 bal = decrypt(token.confidentialBalanceOf(actors[i]));
            assertLe(bal, supply, "balance > supply");
            assertEq(bal, handler.shadowBalance(actors[i]), "balance != shadow");
        }
    }
}
