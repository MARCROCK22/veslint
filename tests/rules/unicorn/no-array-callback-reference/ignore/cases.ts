// unicorn/no-array-callback-reference with `ignore`: callees to ignore after the default ones.
declare function callback(x: number): boolean;
declare const Angular: number[];
declare const foo: { bar: number[]; baz: number[] };
declare const R: { utils: number[]; other: number[] };
declare function make(): number[];
declare const list: number[];

// Ignored.
Angular.forEach(callback);
const a6 = Angular.filter(callback).map(callback);
const a1 = Angular.map(callback);
const a2 = foo.bar.map(callback);
const a3 = R.utils.map(callback);
const a4 = Promise.all([]);
const a5 = _.map(callback);
declare const _: number[];

// Still reported.
const b1 = foo.baz.map(callback);
const b2 = R.other.map(callback);
const b3 = list.map(callback);
const b4 = make().map(callback);
