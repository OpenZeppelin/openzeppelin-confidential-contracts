// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TFHE, einput, euint64 } from "fhevm/lib/TFHE.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { CheckpointConfidential } from "../../utils/structs/CheckpointConfidential.sol";

abstract contract VotesConfidential {
    using TFHE for *;
    using CheckpointConfidential for CheckpointConfidential.TraceEuint64;

    bytes32 private constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    mapping(address account => address) private _delegatee;

    mapping(address delegatee => CheckpointConfidential.TraceEuint64) private _delegateCheckpoints;

    CheckpointConfidential.TraceEuint64 private _totalCheckpoints;

    event DelegateVotesChanged(address indexed delegate, euint64 previousVotes, euint64 newVotes);

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

    function getPastVotes(address account, uint256 timepoint) public view virtual returns (euint64) {
        return _delegateCheckpoints[account].upperLookupRecent(_validateTimepoint(timepoint));
    }

    function getPastTotalSupply(uint256 timepoint) public view virtual returns (euint64) {
        return _totalCheckpoints.upperLookupRecent(_validateTimepoint(timepoint));
    }

    function delegates(address account) public view virtual returns (address) {
        return _delegatee[account];
    }

    function _transferVotingUnits(address from, address to, euint64 amount) internal virtual {
        if (from == address(0)) {
            _push(_totalCheckpoints, _add, amount);
        }
        if (to == address(0)) {
            _push(_totalCheckpoints, _subtract, amount);
        }
        _moveDelegateVotes(delegates(from), delegates(to), amount);
    }

    function _moveDelegateVotes(address from, address to, euint64 amount) internal virtual {
        if (from != to && euint64.unwrap(amount) != 0) {
            if (from != address(0)) {
                (euint64 oldValue, euint64 newValue) = _push(_delegateCheckpoints[from], _subtract, amount);
                emit DelegateVotesChanged(from, oldValue, newValue);
            }
            if (to != address(0)) {
                (euint64 oldValue, euint64 newValue) = _push(_delegateCheckpoints[to], _add, amount);
                emit DelegateVotesChanged(to, oldValue, newValue);
            }
        }
    }

    function _push(
        CheckpointConfidential.TraceEuint64 storage store,
        function(euint64, euint64) returns (euint64) op,
        euint64 delta
    ) private returns (euint64 oldValue, euint64 newValue) {
        return store.push(clock(), op(store.latest(), delta));
    }

    function _add(euint64 a, euint64 b) private returns (euint64) {
        return a.add(b);
    }

    function _subtract(euint64 a, euint64 b) private returns (euint64) {
        return a.sub(b);
    }
}
