// OPTIONS
const VALUE_SIZES = [32, 64];

const defaultOpts = size => ({
  historyTypeName: `TraceEuint${size}`,
  checkpointTypeName: `CheckpointEuint${size}`,
  checkpointFieldName: '_checkpoints',
  valueTypeName: `euint${size}`,
  valueFieldName: '_value',
});

module.exports = {
  VALUE_SIZES,
  OPTS: VALUE_SIZES.map(size => defaultOpts(size)),
};
