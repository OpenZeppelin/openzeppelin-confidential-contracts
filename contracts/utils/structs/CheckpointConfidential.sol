// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TFHE, einput, euint64 } from "fhevm/lib/TFHE.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

library CheckpointConfidential {
    error CheckpointUnorderedInsertion();

    struct TraceEuint64 {
        CheckpointEuint64[] _checkpoints;
    }

    struct CheckpointEuint64 {
        uint48 _key;
        euint64 _value;
    }

    euint64 private constant ENCRYPTED_ZERO = euint64.wrap(0);

    /**
     * @dev Pushes a (`key`, `value`) pair into a TraceEuint64 so that it is stored as the checkpoint.
     *
     * Returns previous value and new value.
     *
     * IMPORTANT: Never accept `key` as a user input, since an arbitrary `type(uint96).max` key set will disable the
     * library.
     */
    function push(
        TraceEuint64 storage self,
        uint48 key,
        euint64 value
    ) internal returns (euint64 oldValue, euint64 newValue) {
        return _insert(self._checkpoints, key, value);
    }

    /**
     * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
     * there is none.
     */
    function lowerLookup(TraceEuint64 storage self, uint96 key) internal view returns (euint64) {
        uint256 len = self._checkpoints.length;
        uint256 pos = _lowerBinaryLookup(self._checkpoints, key, 0, len);
        return pos == len ? ENCRYPTED_ZERO : _unsafeAccess(self._checkpoints, pos)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     */
    function upperLookup(TraceEuint64 storage self, uint96 key) internal view returns (euint64) {
        uint256 len = self._checkpoints.length;
        uint256 pos = _upperBinaryLookup(self._checkpoints, key, 0, len);
        return pos == 0 ? ENCRYPTED_ZERO : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     *
     * NOTE: This is a variant of {upperLookup} that is optimized to find "recent" checkpoint (checkpoints with high
     * keys).
     */
    function upperLookupRecent(TraceEuint64 storage self, uint96 key) internal view returns (euint64) {
        uint256 len = self._checkpoints.length;

        uint256 low = 0;
        uint256 high = len;

        if (len > 5) {
            uint256 mid = len - Math.sqrt(len);
            if (key < _unsafeAccess(self._checkpoints, mid)._key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        uint256 pos = _upperBinaryLookup(self._checkpoints, key, low, high);

        return pos == 0 ? ENCRYPTED_ZERO : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(TraceEuint64 storage self) internal view returns (euint64) {
        uint256 pos = self._checkpoints.length;
        return pos == 0 ? ENCRYPTED_ZERO : _unsafeAccess(self._checkpoints, pos - 1)._value;
    }

    /**
     * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
     * in the most recent checkpoint.
     */
    function latestCheckpoint(
        TraceEuint64 storage self
    ) internal view returns (bool exists, uint96 _key, euint64 _value) {
        uint256 pos = self._checkpoints.length;
        if (pos == 0) {
            return (false, 0, ENCRYPTED_ZERO);
        } else {
            CheckpointEuint64 storage ckpt = _unsafeAccess(self._checkpoints, pos - 1);
            return (true, ckpt._key, ckpt._value);
        }
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

    /**
     * @dev Pushes a (`key`, `value`) pair into an ordered list of checkpoints, either by inserting a new checkpoint,
     * or by updating the last one.
     */
    function _insert(
        CheckpointEuint64[] storage self,
        uint48 key,
        euint64 value
    ) private returns (euint64 oldValue, euint64 newValue) {
        uint256 pos = self.length;

        if (pos > 0) {
            CheckpointEuint64 storage last = _unsafeAccess(self, pos - 1);
            uint96 lastKey = last._key;
            euint64 lastValue = last._value;

            // Checkpoint keys must be non-decreasing.
            if (lastKey > key) {
                revert CheckpointUnorderedInsertion();
            }

            // Update or push new checkpoint
            if (lastKey == key) {
                last._value = value;
            } else {
                self.push(CheckpointEuint64({ _key: key, _value: value }));
            }
            return (lastValue, value);
        } else {
            self.push(CheckpointEuint64({ _key: key, _value: value }));
            return (TFHE.asEuint64(0), value);
        }
    }

    /**
     * @dev Return the index of the first (oldest) checkpoint with key strictly bigger than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _upperBinaryLookup(
        CheckpointEuint64[] storage self,
        uint96 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_unsafeAccess(self, mid)._key > key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return high;
    }

    /**
     * @dev Return the index of the first (oldest) checkpoint with key greater or equal than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _lowerBinaryLookup(
        CheckpointEuint64[] storage self,
        uint96 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_unsafeAccess(self, mid)._key < key) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return high;
    }

    /**
     * @dev Access an element of the array without performing bounds check. The position is assumed to be within bounds.
     */
    function _unsafeAccess(
        CheckpointEuint64[] storage self,
        uint256 pos
    ) private pure returns (CheckpointEuint64 storage result) {
        assembly {
            mstore(0, self.slot)
            result.slot := add(keccak256(0, 0x20), pos)
        }
    }
}
