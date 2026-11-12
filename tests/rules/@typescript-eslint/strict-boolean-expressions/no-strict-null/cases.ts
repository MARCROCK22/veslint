// strict-boolean-expressions: values that are not booleans used as conditions.
declare const bool: boolean;
declare const tru: true;
declare const fals: false;
declare const str: string;
declare const emptyLiteral: '';
declare const literal: 'a';
declare const literals: 'a' | 'b';
declare const template: `id-${string}`;
declare const num: number;
declare const zero: 0;
declare const one: 1;
declare const big: bigint;
declare const bigLiteral: 1n;
declare const obj: object;
declare const arr: number[];
declare const strs: string[];
declare const tuple: [number, string];
declare const fn: () => void;
declare const sym: symbol;
declare const nul: null;
declare const undef: undefined;
declare const voidValue: void;
declare const anyValue: any;
declare const unknownValue: unknown;
declare const neverValue: never;
declare const nBool: boolean | null;
declare const nTrue: true | undefined;
declare const nFalse: false | null;
declare const nStr: string | null;
declare const nLiteral: 'a' | undefined;
declare const nNum: number | undefined;
declare const nOne: 1 | null;
declare const nBig: bigint | null;
declare const nObj: object | null;
declare const nArr: number[] | undefined;
declare const nFn: (() => void) | undefined;
enum NumEnum {
  A,
  B,
}
enum StrEnum {
  A = 'a',
  B = '',
}
declare const numEnum: NumEnum;
declare const strEnum: StrEnum;
declare const nNumEnum: NumEnum | null;
declare const nStrEnum: StrEnum | undefined;
declare const nEnumMember: NumEnum.B | null;
declare const nBothEnums: NumEnum | StrEnum | null;
declare const mixed: string | number;
declare const strOrObj: string | object;
declare const numOrBool: number | boolean;
declare const nMixed: string | number | null;
declare const everything: string | number | boolean | null | object;
declare const nAny: any | null;
type Brand = boolean & { __brand: true };
declare const branded: Brand;
declare const nBranded: Brand | null;
declare const strBrand: string & { __brand: true };
declare function assert(value: unknown, message?: string): asserts value;
declare function assertIsString(value: unknown): asserts value is string;
declare function assertSecond(first: unknown, second: unknown): asserts second;

if (bool) {}
if (tru) {}
if (fals) {}
if (str) {}
if (emptyLiteral) {}
if (literal) {}
if (literals) {}
if (template) {}
if (num) {}
if (zero) {}
if (one) {}
if (big) {}
if (bigLiteral) {}
if (obj) {}
if (arr) {}
if (fn) {}
if (sym) {}
if (nul) {}
if (undef) {}
if (voidValue) {}
if (anyValue) {}
if (unknownValue) {}
if (neverValue) {}
if (nBool) {}
if (nTrue) {}
if (nFalse) {}
if (nStr) {}
if (nLiteral) {}
if (nNum) {}
if (nOne) {}
if (nBig) {}
if (nObj) {}
if (nArr) {}
if (nFn) {}
if (numEnum) {}
if (strEnum) {}
if (nNumEnum) {}
if (nStrEnum) {}
if (nEnumMember) {}
if (nBothEnums) {}
if (mixed) {}
if (strOrObj) {}
if (numOrBool) {}
if (nMixed) {}
if (everything) {}
if (nAny) {}
if (branded) {}
if (nBranded) {}
if (strBrand) {}

// Negations: the suggestions replace the whole `!value`.
if (!bool) {}
if (!str) {}
if (!num) {}
if (!obj) {}
if (!anyValue) {}
if (!nBool) {}
if (!nStr) {}
if (!nNum) {}
if (!nObj) {}
if (!nNumEnum) {}
if (!!nStr) {}
if (!(nNum)) {}
if (!arr.length) {}
if (arr.length) {}
if (str.length) {}
if (nArr?.length) {}
if (!nArr?.length) {}
if (tuple.length) {}
if (arr['length']) {}
if ((arr).length) {}

// Other tests.
while (nStr) {}
do {} while (nNum);
for (; nObj; ) {}
for (;;) {}
for (let i = 0; i < 1, nStr; i++) {}
const ternary = nStr ? 1 : 2;
const nested = (nStr ? nNum : nObj) ? 1 : 2;
const parenthesized = (nStr) ? 1 : 2;

// Logical expressions: the left operand is a condition; the right one only inside a condition.
const and = nStr && nNum;
const or = nStr || nNum;
const chain = nStr && nNum && nObj;
const grouped = nStr && (nNum || nObj);
const nullish = nStr ?? nNum;
const withNullish = (nStr ?? nNum) && nObj;
if (nStr && nNum) {}
if (nStr || nNum || anyValue) {}
if (!(nStr && nNum)) {}
if ((nStr && nNum) || bool) {}
nStr && console.log('side effect');
bool && nStr && console.log('side effect');
(nNum || nObj) && console.log('side effect');
const assigned = bool && (nStr ? 1 : 2);
const inTernary = bool ? nStr && nNum : nObj || nBool;
void (!nStr && nNum);

// Assertion functions.
assert(nStr);
assert(nNum, 'message');
assert(bool && nObj);
assert(nStr || nNum);
assertIsString(nStr);
assertSecond(nStr, nNum);
assert(...[nStr]);
assert();

// Predicates of array methods.
arr.filter(x => x);
arr.filter(x => x > 1);
arr.filter(Boolean);
arr.filter(x => {
  return x;
});
arr.filter((x): number => x);
arr.filter(function (x) {
  return x;
});
arr.filter(async x => true);
arr.filter(async function (x) {
  return true;
});
arr.find((x, index) => index);
arr.findIndex(x => anyValue);
arr.findLast(x => nStr);
arr.findLastIndex(x => unknownValue);
arr.some(x => obj);
arr.every(x => nBool);
arr.map(x => x);
arr.forEach(x => x);
strs.filter(s => s);
strs.filter(s => s.length);
strs.filter(s => !s);
tuple.filter(x => x);
nArr?.filter(x => x);
(arr as number[] | string[]).filter((x: unknown) => x);
arr.filter(anyValue);
arr.filter(fn);
arr.filter(...[fn]);
arr['filter'](x => x);
arr.filter(() => nNum);
arr.filter(x => (x ? nStr : nNum));
arr.filter(<T>(x: T) => x);
arr.filter(<T extends string>(x: unknown) => x as T);
obj.toString();
({ filter: (cb: (x: number) => number) => cb }).filter(x => x);

function generic<T, U extends string, V extends boolean, W extends object | null>(t: T, u: U, v: V, w: W) {
  if (t) {}
  if (u) {}
  if (v) {}
  if (w) {}
  if (!t) {}
  return t && u;
}
class Members {
  private value: string | undefined;
  check() {
    if (this.value) {}
    return this.value ? 1 : 2;
  }
}
export { ternary, nested, parenthesized, and, or, chain, grouped, nullish, withNullish, assigned, inTernary, generic, Members };
