// Reported.
const a = RegExp('[');
const b = new RegExp('.', 'z');
const c = new RegExp('.', 'uv');
const d = new RegExp('a', 'gg');
const e = new RegExp('\\p{Foo}', 'u');
declare const flags: string;
const f = new RegExp('(?<a>)(?<a>)', flags);
// Not reported.
const g = RegExp('.');
const h = new RegExp('[', flags + 'u' === 'u' ? '' : 'x' + flags);
const i = new RegExp('\\p{Letter}', 'u');
export { a, b, c, d, e, f, g, h, i };
