// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984VotesMock} from "./../../../contracts/mocks/token/ERC7984/extensions/ERC7984VotesMock.sol";
import {BaseHandler} from "./BaseHandler.sol";

/// @dev The handler is not a FhevmTest, so it reads plaintext through the invariant test contract.
interface IDecryptor {
    function decryptUint64(euint64 handle) external returns (uint64);
}

/// @dev Managed handler for {ERC7984Votes} vote-accounting invariants (INV-V01, INV-V02).
///
/// Holders and delegatees are drawn from a closed actor set (plus `address(0)` as an
/// "undelegate" target) so the sum-based predicates are complete. Amounts span the full
/// uint64 range, so the encrypted no-op branches (overflowing mint, insufficient burn or
/// transfer → `transferred == 0`) are hit alongside the success paths. ERC7984 balance
/// accounting is trusted (covered by its own suite); balances are only decrypted to steer
/// amounts and count successes. `_setClockOverride` is deliberately not exposed.
contract ERC7984VotesHandler is BaseHandler {
    uint64 internal constant MAX = type(uint64).max;

    ERC7984VotesMock public immutable token;
    IDecryptor public immutable decryptor;

    constructor(ERC7984VotesMock token_, IDecryptor decryptor_) {
        token = token_;
        decryptor = decryptor_;
        _addActor(address(0xA11CE));
        _addActor(address(0xB0B));
        _addActor(address(0xCA201));
        _addActor(address(0xD00D));
    }

    function mint(uint256 toSeed, uint256 amount) external newBlock countCall("mint") {
        address to = _rand(toSeed);
        amount = bound(amount, 0, MAX);
        if (_supply() + amount <= MAX) calls["mint:ok"]++;

        token.$_mint(to, uint64(amount));
    }

    /// @dev Half the time unbounded by balance (an insufficient burn must move no votes), half
    /// the time affordable so the vote-moving success path is well covered.
    function burn(uint256 fromSeed, uint256 amount) external newBlock countCall("burn") {
        address from = _rand(fromSeed);
        uint256 balance = _balance(from);
        amount = _amount(amount, balance);
        if (amount <= balance) calls["burn:ok"]++;

        token.$_burn(from, uint64(amount));
    }

    /// @dev Same split as {burn}: an insufficient transfer must move no votes.
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external newBlock countCall("transfer") {
        address from = _rand(fromSeed);
        address to = _rand(toSeed);
        uint256 balance = _balance(from);
        amount = _amount(amount, balance);
        if (amount <= balance) calls["transfer:ok"]++;

        vm.prank(from);
        token.confidentialTransfer(to, uint64(amount));
    }

    /// @dev Delegate to another actor, to self, or (1-in-(n+1)) to address(0) to undelegate.
    /// Also covers delegation by an account whose balance handle is still uninitialized.
    function delegate(uint256 actorSeed, uint256 delegateeSeed) external newBlock countCall("delegate") {
        address account = _rand(actorSeed);
        uint256 n = this.actorCount();
        address delegatee = delegateeSeed % (n + 1) == n ? address(0) : _rand(delegateeSeed);

        vm.prank(account);
        token.delegate(delegatee);
    }

    /// @dev Odd seeds span the full uint64 range; even seeds are bounded to `balance`.
    function _amount(uint256 seed, uint256 balance) internal pure returns (uint256) {
        return seed % 2 == 0 ? bound(seed, 0, balance) : bound(seed, 0, MAX);
    }

    function _balance(address account) internal returns (uint256) {
        return decryptor.decryptUint64(token.confidentialBalanceOf(account));
    }

    function _supply() internal returns (uint256) {
        return decryptor.decryptUint64(token.confidentialTotalSupply());
    }
}
