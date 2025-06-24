// SPDX-License-Identifier: MIT
// This file was procedurally generated from scripts/generate/templates/CheckpointsConfidential.js.

pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {euint32, euint64} from "fhevm/lib/TFHE.sol";
import {Checkpoints} from "./temporary-Checkpoints.sol";

/**
 * @dev This library defines the `Trace*` struct, for checkpointing values as they change at different points in
 * time, and later looking up past values by block number.
 *
 * To create a history of checkpoints, define a variable type `CheckpointsConfidential.Trace*` in your contract, and store a new
 * checkpoint for the current transaction block using the {push} function.
 */
library CheckpointsConfidential {
    /**
     * @dev A value was attempted to be inserted on a past checkpoint.
     */
    error CheckpointUnorderedInsertion();

    struct TraceEuint32 {
        CheckpointEuint32[] _checkpoints;
    }

    struct CheckpointEuint32 {
        uint256 _key;
        euint32 _value;
    }

    function _toTrace256(TraceEuint32 storage self) private pure returns (Checkpoints.Trace256 storage res) {
        assembly ("memory-safe") {
            res.slot := self.slot
        }

        return res;
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into a TraceEuint32 so that it is stored as the checkpoint.
     *
     * Returns previous value and new value.
     *
     * IMPORTANT: Never accept `key` as a user input, since an arbitrary `type(uint256).max` key set will disable the
     * library.
     */
    function push(
        TraceEuint32 storage self,
        uint256 key,
        euint32 value
    ) internal returns (euint32 oldValue, euint32 newValue) {
        (uint256 oldValueAsUint256, uint256 newValueAsUint256) = Checkpoints.push(
            _toTrace256(self),
            key,
            uint256(euint32.unwrap(value))
        );
        return (euint32.wrap(oldValueAsUint256), euint32.wrap(newValueAsUint256));
    }

    /**
     * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
     * there is none.
     */
    function lowerLookup(TraceEuint32 storage self, uint256 key) internal view returns (euint32) {
        return euint32.wrap(Checkpoints.lowerLookup(_toTrace256(self), key));
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     */
    function upperLookup(TraceEuint32 storage self, uint256 key) internal view returns (euint32) {
        return euint32.wrap(Checkpoints.upperLookup(_toTrace256(self), key));
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     *
     * NOTE: This is a variant of {upperLookup} that is optimized to find "recent" checkpoint (checkpoints with high
     * keys).
     */
    function upperLookupRecent(TraceEuint32 storage self, uint256 key) internal view returns (euint32) {
        return euint32.wrap(Checkpoints.upperLookupRecent(_toTrace256(self), key));
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(TraceEuint32 storage self) internal view returns (euint32) {
        return euint32.wrap(Checkpoints.latest(_toTrace256(self)));
    }

    /**
     * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
     * in the most recent checkpoint.
     */
    function latestCheckpoint(
        TraceEuint32 storage self
    ) internal view returns (bool exists, uint256 _key, euint32 _value) {
        uint256 _valueAsUint256;
        (exists, _key, _valueAsUint256) = Checkpoints.latestCheckpoint(_toTrace256(self));
        return (exists, _key, euint32.wrap(_valueAsUint256));
    }

    /**
     * @dev Returns the number of checkpoints.
     */
    function length(TraceEuint32 storage self) internal view returns (uint256) {
        return self._checkpoints.length;
    }

    /**
     * @dev Returns checkpoint at given position.
     */
    function at(TraceEuint32 storage self, uint32 pos) internal view returns (CheckpointEuint32 memory) {
        return self._checkpoints[pos];
    }

    struct TraceEuint64 {
        CheckpointEuint64[] _checkpoints;
    }

    struct CheckpointEuint64 {
        uint256 _key;
        euint64 _value;
    }

    function _toTrace256(TraceEuint64 storage self) private pure returns (Checkpoints.Trace256 storage res) {
        assembly ("memory-safe") {
            res.slot := self.slot
        }

        return res;
    }

    /**
     * @dev Pushes a (`key`, `value`) pair into a TraceEuint64 so that it is stored as the checkpoint.
     *
     * Returns previous value and new value.
     *
     * IMPORTANT: Never accept `key` as a user input, since an arbitrary `type(uint256).max` key set will disable the
     * library.
     */
    function push(
        TraceEuint64 storage self,
        uint256 key,
        euint64 value
    ) internal returns (euint64 oldValue, euint64 newValue) {
        (uint256 oldValueAsUint256, uint256 newValueAsUint256) = Checkpoints.push(
            _toTrace256(self),
            key,
            uint256(euint64.unwrap(value))
        );
        return (euint64.wrap(oldValueAsUint256), euint64.wrap(newValueAsUint256));
    }

    /**
     * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
     * there is none.
     */
    function lowerLookup(TraceEuint64 storage self, uint256 key) internal view returns (euint64) {
        return euint64.wrap(Checkpoints.lowerLookup(_toTrace256(self), key));
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     */
    function upperLookup(TraceEuint64 storage self, uint256 key) internal view returns (euint64) {
        return euint64.wrap(Checkpoints.upperLookup(_toTrace256(self), key));
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     *
     * NOTE: This is a variant of {upperLookup} that is optimized to find "recent" checkpoint (checkpoints with high
     * keys).
     */
    function upperLookupRecent(TraceEuint64 storage self, uint256 key) internal view returns (euint64) {
        return euint64.wrap(Checkpoints.upperLookupRecent(_toTrace256(self), key));
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(TraceEuint64 storage self) internal view returns (euint64) {
        return euint64.wrap(Checkpoints.latest(_toTrace256(self)));
    }

    /**
     * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
     * in the most recent checkpoint.
     */
    function latestCheckpoint(
        TraceEuint64 storage self
    ) internal view returns (bool exists, uint256 _key, euint64 _value) {
        uint256 _valueAsUint256;
        (exists, _key, _valueAsUint256) = Checkpoints.latestCheckpoint(_toTrace256(self));
        return (exists, _key, euint64.wrap(_valueAsUint256));
    }

    /**
     * @dev Returns the number of checkpoints.
     */
    function length(TraceEuint64 storage self) internal view returns (uint256) {
        return self._checkpoints.length;
    }

    /**
     * @dev Returns checkpoint at given position.
     */
    function at(TraceEuint64 storage self, uint32 pos) internal view returns (CheckpointEuint64 memory) {
        return self._checkpoints[pos];
    }
}
