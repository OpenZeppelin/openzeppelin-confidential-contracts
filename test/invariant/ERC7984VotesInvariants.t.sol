// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/console.sol";
import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {ERC7984VotesMock} from "./../../contracts/mocks/token/ERC7984/extensions/ERC7984VotesMock.sol";
import {ERC7984VotesHandler, IDecryptor} from "./helpers/ERC7984VotesHandler.sol";

/// @dev Invariants INV-V01, INV-V02 from invariants.md — ERC7984Votes vote accounting.
///
/// `_moveDelegateVotes` uses wrapping FHE add/sub, so any desync between vote checkpoints and
/// balances surfaces as a wrapped (~2^64) vote value rather than a revert. These invariants
/// compare decrypted votes against decrypted balances and supply to catch exactly that.
contract ERC7984VotesInvariants is FhevmTest, IDecryptor {
    ERC7984VotesMock internal token;
    ERC7984VotesHandler internal handler;

    function setUp() public override {
        super.setUp(); // deploy FHE host, start log recording
        disableHCUDepthLimit(); // invariant sequences chain many FHE ops per run

        token = new ERC7984VotesMock("Confidential Votes", "CVOTE", "");
        handler = new ERC7984VotesHandler(token, IDecryptor(address(this)));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = ERC7984VotesHandler.mint.selector;
        selectors[1] = ERC7984VotesHandler.burn.selector;
        selectors[2] = ERC7984VotesHandler.transfer.selector;
        selectors[3] = ERC7984VotesHandler.delegate.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev Decryptor callback (see {IDecryptor}). Uninitialized handles decrypt as 0.
    function decryptUint64(euint64 handle) external returns (uint64) {
        return decrypt(handle);
    }

    /// INV-V01: getVotes(d) == Σ balanceOf(a) over accounts a delegating to d.
    function invariant_INV_V01_votesEqualDelegatedBalances() public {
        address[] memory actors = handler.actors();
        for (uint256 i; i < actors.length; ++i) {
            address d = actors[i];
            uint256 expected;
            for (uint256 j; j < actors.length; ++j) {
                if (token.delegates(actors[j]) == d) expected += decrypt(token.confidentialBalanceOf(actors[j]));
            }
            assertEq(uint256(decrypt(token.getVotes(d))), expected, "votes != sum of delegators' balances");
        }
    }

    /// INV-V02: Σ getVotes ≤ totalSupply, with equality when every holder delegates to a non-zero address.
    function invariant_INV_V02_votesBoundedBySupply() public {
        address[] memory actors = handler.actors();
        uint256 sumVotes;
        bool allDelegated = true;
        for (uint256 i; i < actors.length; ++i) {
            sumVotes += decrypt(token.getVotes(actors[i]));
            if (decrypt(token.confidentialBalanceOf(actors[i])) > 0 && token.delegates(actors[i]) == address(0)) {
                allDelegated = false;
            }
        }
        uint256 supply = decrypt(token.confidentialTotalSupply());
        assertLe(sumVotes, supply, "sum of votes > supply");
        if (allDelegated) assertEq(sumVotes, supply, "fully delegated but sum of votes != supply");
    }

    /// @dev Success-vs-no-op split per value-moving action, so a green run with only
    /// encrypted no-ops is visible as weak coverage.
    function afterInvariant() public view {
        string[3] memory keys = ["mint", "burn", "transfer"];
        for (uint256 i; i < keys.length; ++i) {
            console.log(
                keys[i],
                handler.callCount(bytes32(bytes(keys[i]))),
                handler.callCount(bytes32(bytes(string.concat(keys[i], ":ok"))))
            );
        }
    }
}
