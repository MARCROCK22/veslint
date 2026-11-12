// no-require-imports with `allowAsImport`: `import x = require('…')` is allowed, a call is not.
import a = require('a');
import type b = require('b');
const c = require('c');
const d = require?.('d');

export { a, b, c, d };
