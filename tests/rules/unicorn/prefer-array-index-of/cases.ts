// unicorn/prefer-array-index-of: `.indexOf()` instead of `.findIndex(x => x === y)`.
declare const list: number[];
declare const value: number;
declare function get(): number;

const i1 = list.findIndex(x => x === value);
const i2 = list.findIndex(x => value === x);
const i3 = list.findLastIndex(x => x === value);
const i4 = list.findIndex(function (x) { return x === value; });
const i5 = list.findIndex(x => { return x === (value); });
const i6 = list.findIndex(x => x === get());
const i7 = list.findIndex(x => x === 1);

// Not reported.
const z1 = list.findIndex(x => x == value);
const z2 = list.findIndex((x, i) => x === i);
const z3 = list.findIndex(x => x === x + 1);
const z4 = list.findIndex(async x => x === value);
const z5 = list.findIndex(function (x) { return this === x; });
const z6 = list.findIndex(function f(x) { return x === f.length; });
const z7 = list.findIndex(function (x) { return x === arguments.length; });
const z8 = list.findIndex(x => x === value, list);
