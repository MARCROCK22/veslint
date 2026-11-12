// sourceType "commonjs": ESLint adds the CommonJS globals; typescript-eslint's parser reads a script.
const fs = require('fs');
module.exports = { fs };
exports.other = global;
var top = 1;
