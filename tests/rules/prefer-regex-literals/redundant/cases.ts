// Reported (with a suggestion when it can be written as a literal).
const a = new RegExp('abc');
const b = RegExp('abc', 'u');
const c = new RegExp(`a\tb`);
const d = new RegExp(String.raw`\d+`, 'g');
const e = new RegExp('a/b');
const f = new RegExp(/abc/);
const g = new RegExp(/abc/, 'u');
// Not reported.
declare const pattern: string;
const h = new RegExp(pattern);
const i = new RegExp('abc', pattern);
const j = new RegExp(`${pattern}`);
export { a, b, c, d, e, f, g, h, i, j };
