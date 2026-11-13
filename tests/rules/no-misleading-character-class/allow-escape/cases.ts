// Reported.
const a = /^[👍]$/;
const b = /^[Á]$/u;
const c = /^[👶🏻]$/u;
const d = /^[🇯🇵]$/u;
const e = /^[👨‍👩‍👦]$/u;
const f = new RegExp('[👍]');
const g = new RegExp('^[Á]$', 'u');
const h = /^[Á]$/u;
// Not reported.
const i = /^[👍]$/u;
const j = /^[abc]$/;
const k = new RegExp('[👍]', 'u');
export { a, b, c, d, e, f, g, h, i, j, k };
