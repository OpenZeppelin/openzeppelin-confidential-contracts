// OPTIONS
const VALUE_SIZES = [32, 64];

const defaultOpts = size => ({
  historyTypeName: `TraceEuint${size}`,
  valueTypeName: `euint${size}`,
});

module.exports = {
  VALUE_SIZES,
  OPTS: VALUE_SIZES.map(size => defaultOpts(size)),
};
