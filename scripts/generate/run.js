#!/usr/bin/env node

const cp = require('child_process');
const fs = require('fs');
const path = require('path');
const format = require('./format-lines');

function getVersion(path) {
  try {
    return fs.readFileSync(path, 'utf8').match(/\/\/ OpenZeppelin Confidential Contracts \(last updated v[^)]+\)/)[0];
  } catch {
    return null;
  }
}

function generateFromTemplate(file, template, outputPrefix = '', lint = false) {
  const script = path.relative(path.join(__dirname, '../..'), __filename);
  const input = path.join(path.dirname(script), template);
  const output = path.join(outputPrefix, file);
  const version = getVersion(output);
  const content = format(
    '// SPDX-License-Identifier: MIT',
    ...(version ? [version + ` (${file})`] : []),
    `// This file was procedurally generated from ${input}.`,
    '',
    require(template).trimEnd(),
  );

  fs.writeFileSync(output, content);
  lint && cp.execFileSync('prettier', ['--write', output]);
}

// Some templates needs to go through the linter after generation
const needsLinter = ['utils/structs/CheckpointsConfidential.sol'];

// Contracts
for (const [file, template] of Object.entries({
  'utils/structs/CheckpointsConfidential.sol': './templates/CheckpointsConfidential.js',
})) {
  generateFromTemplate(file, template, './contracts/', needsLinter.includes(file));
}

// // Tests
// for (const [file, template] of Object.entries({
//   "utils/structs/Checkpoints.t.sol": "./templates/Checkpoints.t.js",
// })) {
//   generateFromTemplate(file, template, "./test/");
// }
