// Reported.
const a = /^abc[]/;
const b = /foo[]bar/u;
const c = /[[]]/v;
// Not reported.
const d = /^abc[^]/;
const e = /[\[]/;
const f = new RegExp('[]');
export { a, b, c, d, e, f };
