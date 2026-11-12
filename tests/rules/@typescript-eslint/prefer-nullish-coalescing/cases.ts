// Cases of prefer-nullish-coalescing (typescript-eslint 8.62.0). The expected findings are in
// expected.txt, validated against typescript-eslint by tests/rules/reference.sh.
export {};
enum E { A, B }
declare const s: string | undefined;
declare const n: number | null;
declare const b: boolean | undefined;
declare const big: bigint | null;
declare const o: { x: number } | null;
declare const os: { x?: string | null; y: { z?: number } } | undefined;
declare const anyValue: any;
declare const unknownValue: unknown;
declare const nonNullable: string;
declare const v: void | string;
declare const lit: 'a' | null;
declare const tpl: `x${string}` | null;
declare const e: E | undefined;
declare const strOrNum: string | number | null;
declare const branded: (string & { __b: 1 }) | null;
declare const rec: { a?: number; 'b-c'?: number; [k: string]: number | undefined };
declare const k: string;
declare function f(): string | null;

// `||`
export const or1 = s || 'default';
export const or2 = n || 1;
export const or3 = b || true;
export const or4 = big || 1n;
export const or5 = o || { x: 1 };
export const or6 = anyValue || 1;
export const or7 = unknownValue || 1;
export const or8 = nonNullable || 'x';
export const or9 = v || 'x';
export const or10 = lit || 'b';
export const or11 = (s) || 'x';
export const or12 = s || n || 'x';
export const or13 = os?.x || 'y';
export const or14 = f() || 'z';
export const or15 = e || E.A;
export const or16 = strOrNum || 0;
export const or17 = branded || 'q';
export const or18 = tpl || 'x';
export const or19 = (s
  ||
  'x');

// Conditional tests (ignored by default).
if (s || n) {}
while (s || 'x') {
  break;
}
for (; s || 'x';) {
  break;
}
do {} while (s || 'x');
export const t0 = (s || 'x') ? 1 : 2;
if (!(s || 'x')) {}
if ((s || n, o || 1)) {}
if (s || (n && o)) {}
export const c1 = s ? (n || 1) : 2;

// Mixed with `&&`.
export const m1 = s || (n && o);
export const m2 = (s && n) || o;
export const m3 = s || ((n || o) && b);

// `||=`
let mut1: string | undefined;
mut1 ||= 'x';
let mut2: number | null = null;
mut2 ||= 1;
os!.x ||= 'y';

// Conditional expressions.
export const t2 = s ? s : 'x';
export const t3 = !s ? 'x' : s;
export const t4 = s !== undefined ? s : 'x';
export const t5 = s === undefined ? 'x' : s;
export const t6 = n !== null ? n : 1;
export const t7 = n === null ? 1 : n;
export const t8 = s != null ? s : 'x';
export const t9 = s == null ? 'x' : s;
export const t10 = o !== null && o !== undefined ? o : { x: 1 };
export const t11 = o === null || o === undefined ? { x: 1 } : o;
export const t12 = os?.y.z !== undefined ? os.y.z : 0;
export const t13 = os!.y.z ? os!.y.z : 0;
export const t14 = s ? 'other' : 'x';
export const t15 = undefined !== s ? s : 'x';
export const t16 = null != n ? n : 1;
export const t17 = n !== undefined ? n : 1;
export const t18 = s !== null ? s : 'x';
export const t19 = anyValue !== undefined ? anyValue : 1;
export const t20 = os?.x !== undefined && os.x !== null ? os.x : 'x';
export const t21 = (s) ? (s) : 'x';
export const t22 = rec.a ? rec['a'] : 0;
export const t23 = rec['b-c'] ? rec['b-c'] : 0;
export const t24 = rec[k] ? rec[k] : 0;
export const t25 = rec[1] ? rec[1.0] : 0;
export const t26 = rec['a'] ? rec["a"] : 0;
export const t27 = s === undefined || s === null ? 'x' : s;
export const t28 = s !== undefined && s != null ? s : 'x';
export const t29 = null === undefined || s === null ? 'x' : s;
export const t30 = s === undefined && n === null ? 'x' : s;
export const t31 = os?.x ? os.x : 'x';
export const t32 = nonNullable ? nonNullable : 'x';
export const t33 = rec.a !== undefined ? rec.b : 0;
export const t34 = !rec.a ? 0 : rec.a;
export const t35 = !(s) ? 'x' : s;
export const t36 = s ?? s ? s : 'x';

class Holder {
  value: number | undefined;
  get(): number {
    return this.value ? this.value : 0;
  }
}
export const holder = new Holder();

// If statements.
let target: string | undefined;
declare const obj: { field?: number };
if (!target) target = 'x';
if (!target) {
  target = 'x';
}
if (target === undefined) target = 'x';
if (target == null) {
  target = 'x';
}
if (target === null || target === undefined) target = 'x';
if (!target) {
  target = 'x';
  ;
}
if (!target) target += 'x';
if (!target) target = 'x';
else {}
if (target) target = 'x';
if (!obj.field) obj.field = 1;
if (target !== undefined) target = 'x';
if (!target) {
  // a comment
  target = 'x';
}
if (!target) (target = 'x');
