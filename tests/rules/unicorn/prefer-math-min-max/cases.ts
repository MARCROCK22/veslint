// unicorn/prefer-math-min-max: `Math.min()` and `Math.max()` instead of a ternary that compares
// two values and gives one of them.
declare let height: number;
declare const box: { value: number };

const m1 = height > 50 ? 50 : height;
const m2 = height < 50 ? height : 50;
const m3 = height >= 50 ? height : 50;
const m4 = height <= 50 ? 50 : height;
const m5 = box.value > 1 ? 1 : box.value;
const m6 = (height as number) > 2 ? 2 : height;
const m7 = height! > 2 ? 2 : height!;
function f(a: number, b = 1) {
  return a > b ? b : a;
}
function g() {
  return(height > 1 ? 1 : height);
}

// Not reported.
const z1 = height > 50 ? height : 49;
const z2 = height === 50 ? 50 : height;
const z3 = 1n > 2n ? 2n : 1n;
const z4 = new Date() > new Date() ? 1 : 2;
function h(a: string, b = 'x') {
  return a > b ? b : a;
}
function i(text = 'a') {
  const other = 'b';
  return text > other ? other : text;
}
const z5 = (height as unknown as string) > 'a' ? 'a' : height;

// 79.0.0: only suggestions; BigInts known from types, JSDoc or values; effects and comments.
declare let big: bigint;
declare let mixed: bigint | number;
const v1 = big > 10n ? 10n : big;
const v2 = mixed > 10 ? 10 : mixed;
const bigConst = 5n;
const v3 = bigConst > 1n ? 1n : bigConst;
/** @type {bigint} */
const documented = BigInt(1);
const v4 = documented > 0 ? 0 : documented;
const v5 = box.value > 50 ? 50 : box.value;
declare function next(): number;
const v6 = next() > 50 ? 50 : next();
const v7 = height /* keep */ > 50 ? 50 : height;
const v8 = (height, height) > 50 ? 50 : (height, height);
export function withDefault(value = 'x') {
  return value > 'a' ? 'a' : value;
}
export function outer(limit: number) {
  return function inner() {
    return limit > 5 ? 5 : limit;
  };
}
