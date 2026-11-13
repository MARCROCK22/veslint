// Reported.
const a = /\x1f/;
const b = /\u001F/u;
const c = new RegExp('\x0c');
const d = RegExp('\\x1f', 'g');
const e = /(?<a>\x00)\k<a>/;
// Not reported.
const f = /\t\n/;
const g = /\x20/;
const h = new RegExp('\\t');
export { a, b, c, d, e, f, g, h };
