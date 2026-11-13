// Reported (with suggestions).
const a = '\a';
const b = "\'";
const c = `\"${a}\#`;
const d = /\!/;
const e = /[\.]/;
const f = /a\-b/;
const g = /[a\-b]/v;
// Not reported.
const h = '\n\\\'';
const i = `\`\${a}`;
const j = /\.\[\]/;
const k = /[\-a]/;
const l = String.raw`\a`;
export { a, b, c, d, e, f, g, h, i, j, k, l };
