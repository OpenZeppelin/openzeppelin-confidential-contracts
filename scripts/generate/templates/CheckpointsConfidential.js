const format = require('../format-lines');
const { OPTS } = require('./CheckpointsConfidential.opts');

// TEMPLATE
const header = `\
pragma solidity ^0.8.24;

import {${OPTS.map(opt => opt.valueTypeName).join(', ')}} from "@fhevm/solidity/lib/FHE.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Checkpoints} from "./temporary-Checkpoints.sol";

/**
 * @dev This library defines the \`Trace*\` struct, for checkpointing values as they change at different points in
 * time, and later looking up past values by block number.
 *
 * To create a history of checkpoints, define a variable type \`CheckpointsConfidential.Trace*\` in your contract, and store a new
 * checkpoint for the current transaction block using the {push} function.
 */
`;

const libraryUsage = `\
using Checkpoints for Checkpoints.Trace256;
`;

const template = opts => `\
struct ${opts.historyTypeName} {
    Checkpoints.Trace256 _inner;
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
    (uint256 oldValueAsUint256, uint256 newValueAsUint256) = self._inner.push(
        key,
        uint256(${opts.valueTypeName}.unwrap(value))
    );
    oldValue = ${opts.valueTypeName}.wrap(bytes32(oldValueAsUint256));
    newValue = ${opts.valueTypeName}.wrap(bytes32(newValueAsUint256));
}

/**
 * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
 * there is none.
 */
function lowerLookup(${opts.historyTypeName} storage self, uint256 key) internal view returns (${opts.valueTypeName}) {
    return ${opts.valueTypeName}.wrap(bytes32(self._inner.lowerLookup(key)));
}

/**
 * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
 * if there is none.
 */
function upperLookup(${opts.historyTypeName} storage self, uint256 key) internal view returns (${opts.valueTypeName}) {
    return ${opts.valueTypeName}.wrap(bytes32(self._inner.upperLookup(key)));
}

/**
 * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
 * if there is none.
 *
 * NOTE: This is a variant of {upperLookup} that is optimized to find "recent" checkpoint (checkpoints with high
 * keys).
 */
function upperLookupRecent(${opts.historyTypeName} storage self, uint256 key) internal view returns (${opts.valueTypeName}) {
    return ${opts.valueTypeName}.wrap(bytes32(self._inner.upperLookupRecent(key)));
}

/**
 * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
 */
function latest(${opts.historyTypeName} storage self) internal view returns (${opts.valueTypeName}) {
    return ${opts.valueTypeName}.wrap(bytes32(self._inner.latest()));
}

/**
 * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
 * in the most recent checkpoint.
 */
function latestCheckpoint(
    ${opts.historyTypeName} storage self
) internal view returns (bool exists, uint256 key, ${opts.valueTypeName} value) {
    uint256 valueAsUint256;
    (exists, key, valueAsUint256) = self._inner.latestCheckpoint();
    value = ${opts.valueTypeName}.wrap(bytes32(valueAsUint256));
}

/**
 * @dev Returns the number of checkpoints.
 */
function length(${opts.historyTypeName} storage self) internal view returns (uint256) {
    return self._inner.length();
}

/**
 * @dev Returns checkpoint at given position.
 */
function at(${opts.historyTypeName} storage self, uint32 pos) internal view returns (uint256 key, ${opts.valueTypeName} value) {
    Checkpoints.Checkpoint256 memory checkpoint = self._inner.at(pos);
    key = checkpoint._key;
    value = ${opts.valueTypeName}.wrap(bytes32(checkpoint._value));
}
`;

// GENERATE
module.exports = format(
  header.trimEnd(),
  'library CheckpointsConfidential {',
  format(
    [].concat(
      libraryUsage,
      OPTS.map(opts => template(opts)),
    ),
  ).trimEnd(),
  '}',
);
