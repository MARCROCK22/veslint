// Reported.
const a = /(a)|\1b/;
const b = /\1(a)/;
const c = /(a\1)/;
const d = /(?<=(a)\1)b/;
const e = /(?!(a))\1/;
const f = new RegExp('(?<n>a)|\\k<n>');
// Not reported.
const g = /(a)\1/;
const h = /(?<=\1(a))b/;
const i = RegExp('(a)\\1');
export { a, b, c, d, e, f, g, h, i };
