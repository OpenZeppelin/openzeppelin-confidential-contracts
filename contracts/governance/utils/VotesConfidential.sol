// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC6372 } from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import { TFHE, einput, euint64 } from "fhevm/lib/TFHE.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { CheckpointConfidential } from "../../utils/structs/CheckpointConfidential.sol";

abstract contract VotesConfidential is IERC6372 {
    using TFHE for *;
    using CheckpointConfidential for CheckpointConfidential.TraceEuint64;

    bytes32 private constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    mapping(address account => address) private _delegatee;

    mapping(address delegatee => CheckpointConfidential.TraceEuint64) private _delegateCheckpoints;

    CheckpointConfidential.TraceEuint64 private _totalCheckpoints;

    event DelegateVotesChanged(address indexed delegate, euint64 previousVotes, euint64 newVotes);

    /**
     * @dev Emitted when an account changes their delegate.
     */
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /**
     * @dev The clock was incorrectly modified.
     */
    error ERC6372InconsistentClock();

    /**
     * @dev Lookup to future votes is not available.
     */
    error ERC5805FutureLookup(uint256 timepoint, uint48 clock);

    function _validateTimepoint(uint256 timepoint) internal view returns (uint48) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) revert ERC5805FutureLookup(timepoint, currentTimepoint);
        return SafeCast.toUint48(timepoint);
    }

    /**
     * @dev Returns the current amount of votes that `account` has.
     */
    function getVotes(address account) public view virtual returns (euint64) {
        return _delegateCheckpoints[account].latest();
    }

    function clock() public view virtual returns (uint48) {
        return Time.blockNumber();
    }

    function CLOCK_MODE() public view virtual returns (string memory) {
        // Check that the clock was not modified
        if (clock() != Time.blockNumber()) {
            revert ERC6372InconsistentClock();
        }
        return "mode=blocknumber&from=default";
    }

    function getPastVotes(address account, uint256 timepoint) public view virtual returns (euint64) {
        return _delegateCheckpoints[account].upperLookupRecent(_validateTimepoint(timepoint));
    }

    function getPastTotalSupply(uint256 timepoint) public view virtual returns (euint64) {
        return _totalCheckpoints.upperLookupRecent(_validateTimepoint(timepoint));
    }

    function getCurrentTotalSupply() public view virtual returns (euint64) {
        return _totalCheckpoints.latest();
    }

    function delegates(address account) public view virtual returns (address) {
        return _delegatee[account];
    }

    function delegate(address delegatee) public virtual {
        _delegate(msg.sender, delegatee);
    }

    function _delegate(address account, address delegatee) internal virtual {
        address oldDelegate = delegates(account);
        _delegatee[account] = delegatee;

        emit DelegateChanged(account, oldDelegate, delegatee);
        _moveDelegateVotes(oldDelegate, delegatee, _getVotingUnits(account));
    }

    function _transferVotingUnits(address from, address to, euint64 amount) internal virtual {
        if (from == address(0)) {
            euint64 newValue = _totalCheckpoints.latest().add(amount);
            newValue.allowThis();

            _push(_totalCheckpoints, newValue);
        }
        if (to == address(0)) {
            euint64 newValue = _totalCheckpoints.latest().sub(amount);
            newValue.allowThis();

            _push(_totalCheckpoints, newValue);
        }
        _moveDelegateVotes(delegates(from), delegates(to), amount);
    }

    function _moveDelegateVotes(address from, address to, euint64 amount) internal virtual {
        CheckpointConfidential.TraceEuint64 storage store;
        if (from != to && euint64.unwrap(amount) != 0) {
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

    function _push(CheckpointConfidential.TraceEuint64 storage store, euint64 value) private returns (euint64) {
        (euint64 oldValue, ) = store.push(clock(), value);
        return oldValue;
    }

    /**
     * @dev Must return the voting units held by an account.
     */
    function _getVotingUnits(address) internal view virtual returns (euint64);
}
