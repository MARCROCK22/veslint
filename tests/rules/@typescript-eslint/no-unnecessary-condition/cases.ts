// Cases of no-unnecessary-condition (typescript-eslint 8.62.0). The expected findings are in
// expected.txt, validated against typescript-eslint by tests/rules/reference.sh.
export {};
declare const str: string;
declare const num: number;
declare const obj: { a: number };
declare const maybeObj: { a: number } | undefined;
declare const anyValue: any;
declare const unknownValue: unknown;
declare const neverValue: never;
declare const arr: string[];
declare const tuple: [string, number];
declare const lit: 'a';
declare const empty: '';
declare const zero: 0;
declare const one: 1;
declare const yes: true;
declare const no: false;
declare const big0: 0n;
declare const big1: 1n;
declare const u: undefined;
declare const n: null;
declare const strOrUndef: string | undefined;
declare const branded: '' & { __b: 1 };
declare const fn: () => void;
declare const maybeFn: (() => void) | undefined;
declare function generic<T>(x: T): T;

// Truthiness.
if (obj) {}
if (!obj) {}
if (str) {}
if (lit) {}
if (empty) {}
if (zero) {}
if (one) {}
if (yes) {}
if (no) {}
if (big0) {}
if (big1) {}
if (u) {}
if (n) {}
if (anyValue) {}
if (unknownValue) {}
if (neverValue) {}
if (fn) {}
if (branded) {}
if (!!obj) {}
if (obj && str) {}
if (str && obj) {}
if (obj || str) {}
if (!(obj && str)) {}
if (arr[0]) {}
if (tuple[0]) {}
if (tuple[num]) {}
export const ternary = obj ? 1 : 2;
while (obj) {
  break;
}
do {
  break;
} while (obj);
for (; obj;) {
  break;
}
for (;;) {
  break;
}
while (true) {
  break;
}
while (1) {
  break;
}
while (0) {}
while (false) {}
while (2) {
  break;
}
while ('x') {
  break;
}
let flag: boolean | string | { a: number } = true;
flag &&= str;
flag ||= obj;
export const l1 = obj && str;
export const l2 = obj || str;
export const l3 = str || obj;

// Nullish coalescing.
export const n1 = obj ?? 1;
export const n2 = strOrUndef ?? 'x';
export const n3 = u ?? 1;
export const n4 = n ?? 1;
export const n5 = anyValue ?? 1;
export const n6 = arr[0] ?? 'x';
export const n7 = maybeObj?.a ?? 1;
export const n8 = obj.a ?? 1;
declare const optional: { a?: number; b: number };
export const n9 = optional.a ?? 1;
export const n10 = optional.b ?? 1;
let target: string | undefined;
target ??= 'x';
let target2 = 'x';
target2 ??= 'y';
declare const record: Record<string, number>;
export const n11 = record.x ?? 1;
export const n12 = record['x'] ?? 1;
export const n13 = neverValue ?? 1;
export const n14 = (u as undefined | null) ?? 1;

// Comparisons between literal types.
export const c1 = lit === 'a';
export const c2 = lit === 'b';
export const c3 = one > zero;
export const c4 = yes == no;
export const c5 = u === undefined;
export const c6 = n == undefined;
export const c7 = str === undefined;
export const c8 = str == null;
export const c9 = num === null;
export const c10 = strOrUndef === undefined;
export const c11 = big1 > one;
declare const ten: '10';
declare const nine: '9';
declare const tenNumber: 10;
export const c12 = ten < nine;
export const c13 = ten == tenNumber;
export const c14 = one <= one;
export const c15 = n >= zero;
export const c16 = u < one;
export const c17 = big0 == no;
export const c18 = one !== one;
switch (lit) {
  case 'a':
    break;
  case 'b':
    break;
}

// Optional chains.
export const o1 = obj?.a;
export const o2 = maybeObj?.a;
export const o3 = obj?.a.toFixed();
export const o4 = fn?.();
export const o5 = maybeFn?.();
export const o6 = arr?.[0];
export const o7 = arr[0]?.length;
declare const nested: { inner?: { value: string } };
export const o8 = nested.inner?.value;
export const o9 = nested.inner?.value?.length;
declare const union: { a: { b: string } } | null;
export const o10 = union?.a?.b;
export const o11 = (obj)?.a;
export const o12 = obj!?.a;

// Array predicate callbacks.
arr.filter(x => x);
arr.filter(() => true);
arr.filter(() => obj);
arr.filter(() => undefined);
arr.find(function () {
  return 1;
});
arr.some(x => x.length > 0);
const isFilled = (x: string): boolean => !!x;
arr.filter(isFilled);
const alwaysTrue = (): true => true;
arr.filter(alwaysTrue);
arr.every(generic);
tuple.filter(() => 0);
arr['filter'](() => obj);

// Type predicates (only with checkTypePredicates).
declare function isString(x: unknown): x is string;
declare function assertTruthy(x: unknown): asserts x;
declare function assertString(x: unknown): asserts x is string;
isString(str);
isString(num);
isString(strOrUndef);
assertTruthy(obj);
assertTruthy(str);
assertString(str);
isString(anyValue);
isString(...arr);

// Generics.
export function g<T>(x: T): T | number {
  if (x) {}
  return x ?? 1;
}
export function h<T extends string>(x: T): void {
  if (x) {}
}
export function k<T extends object>(x: T): void {
  if (x) {}
}

// Callbacks judged by their signature, and chains with `!`.
const alwaysFalse = (): false => false;
arr.filter(alwaysFalse);
arr.filter(() => {
  const value = 0;
  return value;
});
declare const deep: { a?: { b: string } };
export const d1 = deep.a?.b! ?? 'x';
export const d2 = (deep.a?.b)?.length;
export const d3 = deep.a!?.b;
export const d4 = maybeFn!?.();

// The left operand of a comparison is typed as a whole, a negation included.
const negatedLeft1 = !1 < 2;
const negatedLeft2 = (!0) === true;
