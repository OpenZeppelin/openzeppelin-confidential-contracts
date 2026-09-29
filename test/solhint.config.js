const base = require('../solhint.config.js');

// Test files follow Foundry naming conventions (`setUp`, `test_*`, `testFuzz_*`,
// `invariant_*`) that intentionally violate mixedCase, so that rule is relaxed here.
// All other contract rules still apply.
module.exports = {
  ...base,
  rules: {
    ...base.rules,
    'func-name-mixedcase': 'off',
  },
};
