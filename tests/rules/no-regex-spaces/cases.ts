// Reported (fixed when the pattern is written as it is).
const a = /foo   bar/;
const b = /foo  +bar/;
const c = new RegExp('foo   bar');
const d = RegExp('a  b', 'u');
const e = new RegExp('\x20  x');
// Not reported.
const f = /foo {3}bar/;
const g = /[  ]/;
const h = /a +b/;
export { a, b, c, d, e, f, g, h };
