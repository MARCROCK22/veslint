declare const text: string;
declare const num: number;
declare const letters: 'a' | 'b';
declare const tagged: string & { tag: 1 };
declare const other: number;
declare function tag(strings: TemplateStringsArray, ...values: unknown[]): string;
enum Letter {
  A = 'a',
  B = 'b',
}

// A single interpolation of a string: reported from two code units before the expression.
const a = `${text}`;
const b = `${ text }`;
const c = `${(text)}`;
const d = `${
text}`;
const e = `${'literal'}`;
const f = `${letters}`;
const g = `${tagged}`;
const h = `${Letter.A}`;
function generic<T extends string>(value: T): string {
  return `${value}`;
}
// Not a string: the interpolations are checked one by one.
const i = `${num}`;
const j = `${1}`;
const k = `${undefined}`;
function unconstrained<T>(value: T): string {
  return `${value}`;
}

// Literals, undefined, Infinity, NaN and templates inside a template.
const l = `a${'b'}c`;
const m = `a${1}c${true}d${null}e${undefined}f${Infinity}g${NaN}h${/re/}i${1n}`;
const n = `a${`inner`}b${`x${other}y`}c`;
const o = `${'a'}${'b'}`;
const p = `x${other}y${'z'}`;
// A whitespace literal followed by a line break is allowed.
const q = `a${'  '}
b`;
const r = `a${''}
b`;
const s = `a${`  `}
b`;
const t = `a${'x'}
b`;
const u = `a${'  '}b`;
// Comments inside the interpolation, and tagged templates.
const v = `a${/* keep */ 'b'}c`;
const w = `${/* keep */ text}`;
const x = tag`${'a'}`;

// Template literal types.
type A = `${string}`;
type B = `${'a'}`;
type C = `${'a' | 'b'}`;
type D = `a${'b'}c`;
type E = `a${null}b${undefined}c${1}d${true}e${-1}f${`x`}g${`x${string}`}`;
type F<T extends string> = `${T}`;
type G = `${Letter.A}`;
type H = `${Letter}`;
type I = `a${'  '}
b`;
type J = `a${/* keep */ 'b'}`;
type K = `${number}`;

export { a, b, c, d, e, f, g, h, generic, i, j, k, unconstrained, l, m, n, o, p, q, r, s, t, u, v, w, x };
export type { A, B, C, D, E, F, G, H, I, J, K };
