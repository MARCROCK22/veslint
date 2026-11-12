// no-require-imports with its default options: every call of a `require` the file does not declare
// and every `import x = require('…')`.
const a = require('a');
require('b');
const c = require?.('c');
const d = (require)('d');
const e = require<unknown>('e');
const f = require(`f`);
const g = require(`g${a}`);
const h = require(...[a]);
const i = require();
const j = require(1, 2);
const k = require('k').default;
const l = require('l') as unknown;
const m = <unknown>require('m');
const n = [require('n'), (require('o'))];
const p = require(/* comment */ 'p');
const p2 = require('escaped');
import q = require('q');
import type r = require('r');
declare module 'declared-module' {
  import s = require('s');
  const t: typeof s;
}

// Not a call of `require` itself.
const u = new require('u');
const v = require.resolve('v');
const w = require`w`;
const x = window.require('x');
const y = require!('y');
import z = a.b;

// A `require` the file declares is not CommonJS's.
function load(require: (path: string) => unknown) {
  return [require('load'), require?.('load')];
}
namespace Local {
  const require = (path: string) => path;
  export const loaded = require('local');
  export function inner() {
    return require('inner');
  }
}
class Loader {
  require(path: string) {
    return path;
  }
  load() {
    return this.require('member');
  }
}

export { a, c, d, e, f, g, h, i, j, k, l, m, n, p, p2, q, r, u, v, w, x, y, z, load, Loader };
