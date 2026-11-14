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

// 79.0.0: with TypeScript's types, a search value that is not assignable to the parameter of
// `indexOf()` is left (the upstream test, without a program, reports it); receivers known not to
// be arrays; comments in the callback.
const sizes = ['small', 'medium', 'large'] as const;
declare const input: string;
sizes.findIndex(value => value === input);
sizes.findLastIndex(value => value === input);
declare const wide: string[];
wide.findIndex(value => value === input);
declare const custom: { findIndex(cb: (x: string) => boolean): number };
custom.findIndex(value => value === input);
wide.findIndex(value => /* keep */ value === input);
wide.findIndex(function (value) { return value === input; });
