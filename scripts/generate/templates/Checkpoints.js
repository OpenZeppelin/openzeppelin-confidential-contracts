const format = require("../format-lines");
const { OPTS } = require("./Checkpoints.opts");

// TEMPLATE
const header = `\
pragma solidity ^0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ${OPTS.map((opt) => opt.valueTypeName).join(", ")} } from "fhevm/lib/TFHE.sol";

/**
 * @dev This library defines the \`Trace*\` struct, for checkpointing values as they change at different points in
 * time, and later looking up past values by block number.
 *
 * To create a history of checkpoints, define a variable type \`Checkpoints.Trace*\` in your contract, and store a new
 * checkpoint for the current transaction block using the {push} function.
 */
`;

const errors = `\
/**
 * @dev A value was attempted to be inserted on a past checkpoint.
 */
error CheckpointUnorderedInsertion();
`;

const baseImplementation = `\
struct TraceBytes32 {
    CheckpointBytes32[] _checkpoints;
}

struct CheckpointBytes32 {
    uint256 _key;
    bytes32 _value;
}

bytes32 private constant ZERO = bytes32(0);

/**
 * @dev Pushes a (\`key\`, \`value\`) pair into a TraceBytes32 so that it is stored as the checkpoint.
 *
 * Returns previous value and new value.
 *
 * IMPORTANT: Never accept \`key\` as a user input, since an arbitrary \`type(uint96).max\` key set will disable the
 * library.
 */
function push(
    TraceBytes32 storage self,
    uint256 key,
    bytes32 value
) internal returns (bytes32 oldValue, bytes32 newValue) {
    return _insert(self._checkpoints, key, value);
}

/**
 * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
 * there is none.
 */
function lowerLookup(TraceBytes32 storage self, uint256 key) internal view returns (bytes32) {
    uint256 len = self._checkpoints.length;
    uint256 pos = _lowerBinaryLookup(self._checkpoints, key, 0, len);
    return pos == len ? ZERO : _unsafeAccess(self._checkpoints, pos)._value;
}

/**
 * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
 * if there is none.
 */
function upperLookup(TraceBytes32 storage self, uint256 key) internal view returns (bytes32) {
    uint256 len = self._checkpoints.length;
    uint256 pos = _upperBinaryLookup(self._checkpoints, key, 0, len);
    return pos == 0 ? ZERO : _unsafeAccess(self._checkpoints, pos - 1)._value;
}

/**
 * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
 * if there is none.
 *
 * NOTE: This is a variant of {upperLookup} that is optimized to find "recent" checkpoint (checkpoints with high
 * keys).
 */
function upperLookupRecent(TraceBytes32 storage self, uint256 key) internal view returns (bytes32) {
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

    return pos == 0 ? ZERO : _unsafeAccess(self._checkpoints, pos - 1)._value;
}

/**
 * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
 */
function latest(TraceBytes32 storage self) internal view returns (bytes32) {
    uint256 pos = self._checkpoints.length;
    return pos == 0 ? ZERO : _unsafeAccess(self._checkpoints, pos - 1)._value;
}

/**
 * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
 * in the most recent checkpoint.
 */
function latestCheckpoint(
    TraceBytes32 storage self
) internal view returns (bool exists, uint256 _key, bytes32 _value) {
    uint256 pos = self._checkpoints.length;
    if (pos == 0) {
        return (false, 0, ZERO);
    } else {
        CheckpointBytes32 storage ckpt = _unsafeAccess(self._checkpoints, pos - 1);
        return (true, ckpt._key, ckpt._value);
    }
}

/**
 * @dev Returns the number of checkpoints.
 */
function length(TraceBytes32 storage self) internal view returns (uint256) {
    return self._checkpoints.length;
}

/**
 * @dev Returns checkpoint at given position.
 */
function at(TraceBytes32 storage self, uint32 pos) internal view returns (CheckpointBytes32 memory) {
    return self._checkpoints[pos];
}

/**
 * @dev Pushes a (\`key\`, \`value\`) pair into an ordered list of checkpoints, either by inserting a new checkpoint,
 * or by updating the last one.
 */
function _insert(
    CheckpointBytes32[] storage self,
    uint256 key,
    bytes32 value
) private returns (bytes32 oldValue, bytes32 newValue) {
    uint256 pos = self.length;

    if (pos > 0) {
        CheckpointBytes32 storage last = _unsafeAccess(self, pos - 1);
        uint256 lastKey = last._key;
        bytes32 lastValue = last._value;

        // Checkpoint keys must be non-decreasing.
        if (lastKey > key) {
            revert CheckpointUnorderedInsertion();
        }

        // Update or push new checkpoint
        if (lastKey == key) {
            last._value = value;
        } else {
            self.push(CheckpointBytes32({ _key: key, _value: value }));
        }
        return (lastValue, value);
    } else {
        self.push(CheckpointBytes32({ _key: key, _value: value }));
        return (ZERO, value);
    }
}

/**
 * @dev Return the index of the first (oldest) checkpoint with key strictly bigger than the search key, or \`high\`
 * if there is none. \`low\` and \`high\` define a section where to do the search, with inclusive \`low\` and exclusive
 * \`high\`.
 *
 * WARNING: \`high\` should not be greater than the array's length.
 */
function _upperBinaryLookup(
    CheckpointBytes32[] storage self,
    uint256 key,
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
 * @dev Return the index of the first (oldest) checkpoint with key greater or equal than the search key, or \`high\`
 * if there is none. \`low\` and \`high\` define a section where to do the search, with inclusive \`low\` and exclusive
 * \`high\`.
 *
 * WARNING: \`high\` should not be greater than the array's length.
 */
function _lowerBinaryLookup(
    CheckpointBytes32[] storage self,
    uint256 key,
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
    CheckpointBytes32[] storage self,
    uint256 pos
) private pure returns (CheckpointBytes32 storage result) {
    assembly {
        mstore(0, self.slot)
        result.slot := add(keccak256(0, 0x20), mul(pos, 2))
    }
}
`;

const template = (opts) => `\
struct ${opts.historyTypeName} {
    ${opts.checkpointTypeName}[] ${opts.checkpointFieldName};
}

struct ${opts.checkpointTypeName} {
    uint256 _key;
    ${opts.valueTypeName} ${opts.valueFieldName};
}

/**
 * @dev Pushes a (\`key\`, \`value\`) pair into a ${opts.historyTypeName} so that it is stored as the checkpoint.
 *
 * Returns previous value and new value.
 *
 * IMPORTANT: Never accept \`key\` as a user input, since an arbitrary \`type(uint256).max\` key set will disable the
 * library.
 */
function push(
    ${opts.historyTypeName} storage self,
    uint256 key,
    ${opts.valueTypeName} value
) internal returns (${opts.valueTypeName} oldValue, ${opts.valueTypeName} newValue) {
    TraceBytes32 storage selfAsTraceBytes32;
    assembly {
        selfAsTraceBytes32.slot := self.slot
    }

    bytes32 oldValueAsBytes32;
    bytes32 newValueAsBytes32;

    (oldValueAsBytes32, newValueAsBytes32) = push(selfAsTraceBytes32, key, bytes32(${opts.valueTypeName}.unwrap(value)));
    return (${opts.valueTypeName}.wrap(uint256(oldValueAsBytes32)), ${opts.valueTypeName}.wrap(uint256(newValueAsBytes32)));
}

/**
 * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
 * there is none.
 */
function lowerLookup(${opts.historyTypeName} storage self, uint256 key) internal view returns (${opts.valueTypeName}) {
    TraceBytes32 storage selfAsTraceBytes32;
    assembly {
        selfAsTraceBytes32.slot := self.slot
    }

    bytes32 resAsBytes32 = lowerLookup(selfAsTraceBytes32, key);
    return ${opts.valueTypeName}.wrap(uint256(resAsBytes32));
}

/**
 * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
 * if there is none.
 */
function upperLookup(${opts.historyTypeName} storage self, uint256 key) internal view returns (${opts.valueTypeName}) {
    TraceBytes32 storage selfAsTraceBytes32;
    assembly {
        selfAsTraceBytes32.slot := self.slot
    }

    bytes32 resAsBytes32 = upperLookup(selfAsTraceBytes32, key);
    return ${opts.valueTypeName}.wrap(uint256(resAsBytes32));
}

/**
 * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
 * if there is none.
 *
 * NOTE: This is a variant of {upperLookup} that is optimized to find "recent" checkpoint (checkpoints with high
 * keys).
 */
function upperLookupRecent(${opts.historyTypeName} storage self, uint256 key) internal view returns (${opts.valueTypeName}) {
    TraceBytes32 storage selfAsTraceBytes32;
    assembly {
        selfAsTraceBytes32.slot := self.slot
    }

    bytes32 resAsBytes32 = upperLookupRecent(selfAsTraceBytes32, key);
    return ${opts.valueTypeName}.wrap(uint256(resAsBytes32));
}

/**
 * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
 */
function latest(${opts.historyTypeName} storage self) internal view returns (${opts.valueTypeName}) {
    TraceBytes32 storage selfAsTraceBytes32;
    assembly {
        selfAsTraceBytes32.slot := self.slot
    }

    bytes32 resAsBytes32 = latest(selfAsTraceBytes32);
    return ${opts.valueTypeName}.wrap(uint256(resAsBytes32));
}

/**
 * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
 * in the most recent checkpoint.
 */
function latestCheckpoint(
    ${opts.historyTypeName} storage self
) internal view returns (bool exists, uint256 _key, ${opts.valueTypeName} ${opts.valueFieldName}) {
    TraceBytes32 storage selfAsTraceBytes32;
    assembly {
        selfAsTraceBytes32.slot := self.slot
    }

    bytes32 ${opts.valueFieldName}AsBytes32;
    (exists, _key, ${opts.valueFieldName}AsBytes32) = latestCheckpoint(selfAsTraceBytes32);

    return (exists, _key, ${opts.valueTypeName}.wrap(uint256(${opts.valueFieldName}AsBytes32)));
}

/**
 * @dev Returns the number of checkpoints.
 */
function length(${opts.historyTypeName} storage self) internal view returns (uint256) {
    return self.${opts.checkpointFieldName}.length;
}

/**
 * @dev Returns checkpoint at given position.
 */
function at(${opts.historyTypeName} storage self, uint32 pos) internal view returns (${opts.checkpointTypeName} memory) {
    return self.${opts.checkpointFieldName}[pos];
}
`;

// GENERATE
module.exports = format(
  header.trimEnd(),
  "library Checkpoints {",
  format(
    [].concat(
      errors,
      baseImplementation,
      OPTS.map((opts) => template(opts)),
    ),
  ).trimEnd(),
  "}",
);
