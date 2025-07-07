// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

import {CheckpointsConfidential} from "../../utils/structs/CheckpointsConfidential.sol";

abstract contract VotesConfidential is Nonces, EIP712, IERC6372 {
    using FHE for *;
    using CheckpointsConfidential for CheckpointsConfidential.TraceEuint64;

    bytes32 private constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    mapping(address account => address) private _delegatee;

    mapping(address delegatee => CheckpointsConfidential.TraceEuint64) private _delegateCheckpoints;

    CheckpointsConfidential.TraceEuint64 private _totalCheckpoints;

    /// @dev The signature used has expired.
    error VotesExpiredSignature(uint256 expiry);

    /// @dev Emitted when a token transfer or delegate change results in changes to a delegate's number of voting units.
    event DelegateVotesChanged(address indexed delegate, euint64 previousVotes, euint64 newVotes);

    /// @dev Emitted when an account changes their delegate.
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @dev The clock was incorrectly modified.
    error ERC6372InconsistentClock();

    /// @dev Lookup to future votes is not available.
    error ERC5805FutureLookup(uint256 timepoint, uint48 clock);

    /**
     * @dev Clock used for flagging checkpoints. Can be overridden to implement timestamp based
     * checkpoints (and voting), in which case {CLOCK_MODE} should be overridden as well to match.
     */
    function clock() public view virtual returns (uint48) {
        return Time.blockNumber();
    }

    /**
     * @dev Machine-readable description of the clock as specified in ERC-6372.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory) {
        // Check that the clock was not modified
        if (clock() != Time.blockNumber()) {
            revert ERC6372InconsistentClock();
        }
        return "mode=blocknumber&from=default";
    }

    /// @dev Returns the current amount of votes that `account` has.
    function getVotes(address account) public view virtual returns (euint64) {
        return _delegateCheckpoints[account].latest();
    }

    /**
     * @dev Returns the amount of votes that `account` had at a specific moment in the past. If the {clock} is
     * configured to use block numbers, this will return the value at the end of the corresponding block.
     *
     * Requirements:
     *
     * - `timepoint` must be in the past. If operating using block numbers, the block must be already mined.
     */
    function getPastVotes(address account, uint256 timepoint) public view virtual returns (euint64) {
        return _delegateCheckpoints[account].upperLookupRecent(_validateTimepoint(timepoint));
    }

    /**
     * @dev Returns the total supply of votes available at a specific moment in the past. If the {clock} is
     * configured to use block numbers, this will return the value at the end of the corresponding block.
     *
     * NOTE: This value is the sum of all available votes, which is not necessarily the sum of all delegated votes.
     * Votes that have not been delegated are still part of total supply, even though they would not participate in a
     * vote.
     *
     * Requirements:
     *
     * - `timepoint` must be in the past. If operating using block numbers, the block must be already mined.
     */
    function getPastTotalSupply(uint256 timepoint) public view virtual returns (euint64) {
        return _totalCheckpoints.upperLookupRecent(_validateTimepoint(timepoint));
    }

    /**
     * @dev Returns the current total supply of votes as an encrypted uint64 (euint64). Must be implemented
     * by the derived contract.
     */
    function totalSupply() public view virtual returns (euint64);

    /// @dev Returns the delegate that `account` has chosen.
    function delegates(address account) public view virtual returns (address) {
        return _delegatee[account];
    }

    /// @dev Delegates votes from the sender to `delegatee`.
    function delegate(address delegatee) public virtual {
        _delegate(msg.sender, delegatee);
    }

    /// @dev Delegates votes from an EOA to `delegatee` via an ECDSA signature.
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > expiry) {
            revert VotesExpiredSignature(expiry);
        }

        address signer = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry))),
            v,
            r,
            s
        );

        _useCheckedNonce(signer, nonce);
        _delegate(signer, delegatee);
    }

    /**
     * @dev Delegate all of `account`'s voting units to `delegatee`.
     *
     * Emits events {IVotes-DelegateChanged} and {IVotes-DelegateVotesChanged}.
     */
    function _delegate(address account, address delegatee) internal virtual {
        address oldDelegate = delegates(account);
        _delegatee[account] = delegatee;

        emit DelegateChanged(account, oldDelegate, delegatee);
        _moveDelegateVotes(oldDelegate, delegatee, _getVotingUnits(account));
    }

    /**
     * @dev Transfers, mints, or burns voting units. To register a mint, `from` should be zero. To register a burn, `to`
     * should be zero. Total supply of voting units will be adjusted with mints and burns.
     *
     * WARNING: Must be called after {totalSupply} is updated.
     */
    function _transferVotingUnits(address from, address to, euint64 amount) internal virtual {
        if (from == address(0) || to == address(0)) {
            _push(_totalCheckpoints, totalSupply());
        }
        _moveDelegateVotes(delegates(from), delegates(to), amount);
    }

    /**
     * @dev Moves delegated votes from one delegate to another.
     */
    function _moveDelegateVotes(address from, address to, euint64 amount) internal virtual {
        CheckpointsConfidential.TraceEuint64 storage store;
        if (from != to && FHE.isInitialized(amount)) {
            if (from != address(0)) {
                store = _delegateCheckpoints[from];
                euint64 newValue = store.latest().sub(amount);
                newValue.allowThis();
                newValue.allow(from);
                euint64 oldValue = _push(store, newValue);
                emit DelegateVotesChanged(from, oldValue, newValue);
            }
            if (to != address(0)) {
                store = _delegateCheckpoints[to];
                euint64 newValue = store.latest().add(amount);
                newValue.allowThis();
                newValue.allow(to);
                euint64 oldValue = _push(store, newValue);
                emit DelegateVotesChanged(to, oldValue, newValue);
            }
        }
    }

    /// @dev Validate that a timepoint is in the past, and return it as a uint48.
    function _validateTimepoint(uint256 timepoint) internal view returns (uint48) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) revert ERC5805FutureLookup(timepoint, currentTimepoint);
        return SafeCast.toUint48(timepoint);
    }

    /**
     * @dev Must return the voting units held by an account.
     */
    function _getVotingUnits(address) internal view virtual returns (euint64);

    function _push(CheckpointsConfidential.TraceEuint64 storage store, euint64 value) private returns (euint64) {
        (euint64 oldValue, ) = store.push(clock(), value);
        return oldValue;
    }
}
