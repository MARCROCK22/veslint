// no-require-imports with `allow`: a string or a template without substitutions whose value one
// of the patterns (`new RegExp(pattern, 'u')`) matches anywhere is allowed.
const a = require('./package.json');
const b = require('../dir/package.json');
const c = require(`./package.json`);
import d = require('./sub/package.json');
const e = require('allowed-module');
const f = require('Upper');
const g = require('😀');
const h = require('\x41BC');
const i = require('CASE');
const j = require(('./package.json'));

// Not matched, or without a static value.
const k = require('./package.jsonc');
const l = require('not-allowed-module');
const m = require('lower');
const n = require('😀😀');
const o = require(`./${a}/package.json`);
const p = require(a);
import q = require('data.json');
const r = require('caser');

export { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r };
