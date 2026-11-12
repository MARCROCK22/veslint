declare const text: string;
declare const num: number;
declare const flag: boolean;
declare const big: bigint;
declare const texts: string[];
declare const pattern: `a${string}`;
declare const both: string | number;
declare const small: 1 | 2;
enum Letter {
  A = 'a',
}
declare const letter: Letter;

// Concatenating ''.
let changing: string = text;
changing += '';
changing += "";
let mixed: string | number = both;
mixed += '';
const a = text + '';
const b = (text) + '';
const c = '' + text;
const d = '' + num;
const e = text + `` + text;

// Calling a built-in conversion function.
const f = String(text);
const g = Number(num);
const h = Boolean(flag);
const i = BigInt(big);
const j = String(num);
const k = (String)(text);
const l = String(...texts);
const m = String();
function constrained<T extends string>(value: T): string {
  return String(value);
}

// Calling .toString() on a string.
const n = text.toString();
const o = text?.toString();
const p = (text).toString();
const q = pattern.toString();
const r = letter.toString();
const s = Letter.A.toString();
const t = num.toString();

// Unary operators.
const u = !!flag;
const v = !!(flag);
const w = !(!flag);
const x = !!!flag;
const y = !!text;
const z = +num;
const aa = +(num);
const ab = +text;
const ac = ~~1;
const ad = ~~small;
const ae = ~~1.5;
const af = ~~num;

export { a, b, c, d, e, f, g, h, i, j, k, l, m, constrained, n, o, p, q, r, s, t };
export { u, v, w, x, y, z, aa, ab, ac, ad, ae, af };
