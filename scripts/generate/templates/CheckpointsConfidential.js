const format = require('../format-lines');
const { OPTS } = require('./CheckpointsConfidential.opts');

// TEMPLATE
const header = `\
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {${OPTS.map(opt => opt.valueTypeName).join(', ')}} from "fhevm/lib/TFHE.sol";
import {Checkpoints} from "./temporary-Checkpoints.sol";

/**
 * @dev This library defines the \`Trace*\` struct, for checkpointing values as they change at different points in
 * time, and later looking up past values by block number.
 *
 * To create a history of checkpoints, define a variable type \`CheckpointsConfidential.Trace*\` in your contract, and store a new
 * checkpoint for the current transaction block using the {push} function.
 */
`;

const errors = `\
/**
 * @dev A value was attempted to be inserted on a past checkpoint.
 */
error CheckpointUnorderedInsertion();
`;

const template = opts => `\
struct ${opts.historyTypeName} {
    ${opts.checkpointTypeName}[] ${opts.checkpointFieldName};
}

struct ${opts.checkpointTypeName} {
    uint256 _key;
    ${opts.valueTypeName} ${opts.valueFieldName};
}

function _toTrace256(${opts.historyTypeName} storage self) private pure returns (Checkpoints.Trace256 storage res) {
    assembly ("memory-safe") {
        res.slot := self.slot
    }

    return res;
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
    (uint256 oldValueAsUint256, uint256 newValueAsUint256) = Checkpoints.push(
        _toTrace256(self),
        key,
        uint256(${opts.valueTypeName}.unwrap(value))
    );
    return (${opts.valueTypeName}.wrap(oldValueAsUint256), ${opts.valueTypeName}.wrap(newValueAsUint256));
}

/**
 * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
 * there is none.
 */
function lowerLookup(${opts.historyTypeName} storage self, uint256 key) internal view returns (${opts.valueTypeName}) {
    return ${opts.valueTypeName}.wrap(Checkpoints.lowerLookup(_toTrace256(self), key));
}

/**
 * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
 * if there is none.
 */
function upperLookup(${opts.historyTypeName} storage self, uint256 key) internal view returns (${opts.valueTypeName}) {
    return ${opts.valueTypeName}.wrap(Checkpoints.upperLookup(_toTrace256(self), key));
}

/**
 * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
 * if there is none.
 *
 * NOTE: This is a variant of {upperLookup} that is optimized to find "recent" checkpoint (checkpoints with high
 * keys).
 */
function upperLookupRecent(${opts.historyTypeName} storage self, uint256 key) internal view returns (${opts.valueTypeName}) {
    return ${opts.valueTypeName}.wrap(Checkpoints.upperLookupRecent(_toTrace256(self), key));
}

/**
 * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
 */
function latest(${opts.historyTypeName} storage self) internal view returns (${opts.valueTypeName}) {
    return ${opts.valueTypeName}.wrap(Checkpoints.latest(_toTrace256(self)));
}

/**
 * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
 * in the most recent checkpoint.
 */
function latestCheckpoint(
    ${opts.historyTypeName} storage self
) internal view returns (bool exists, uint256 _key, ${opts.valueTypeName} ${opts.valueFieldName}) {
    uint256 ${opts.valueFieldName}AsUint256;
    (exists, _key, ${opts.valueFieldName}AsUint256) = Checkpoints.latestCheckpoint(_toTrace256(self));
    return (exists, _key, ${opts.valueTypeName}.wrap(${opts.valueFieldName}AsUint256));
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
  'library CheckpointsConfidential {',
  format(
    [].concat(
      errors,
      OPTS.map(opts => template(opts)),
    ),
  ).trimEnd(),
  '}',
);
