// unicorn/prefer-array-flat: `.flat()` instead of legacy ways to flatten an array.
declare const nested: number[][];
declare const maybe: number[] | number;
declare const _: { flatten(a: unknown): number[] };
declare function flattenDeep(a: unknown): number[];

const f1 = nested.flatMap(x => x);
const f2 = nested?.flatMap(x => x);
const f3 = nested.reduce((a, b) => a.concat(b), []);
const f4 = nested.reduce((a, b) => [...a, ...b], []);
const f5 = [].concat(maybe);
const f6 = [].concat(...nested);
const f7 = [].concat.apply([], nested);
const f8 = Array.prototype.concat.call([], maybe);
const f9 = Array.prototype.concat.call([], ...nested);
const f10 = _.flatten(nested);
const f11 = [].concat(/* keep */ maybe);
const f12 = [].concat(nested /* keep */);
function f() {
  return[].concat(maybe);
}

// Not reported.
const z1 = nested.flatMap(x => [x]);
const z2 = nested.flatMap((x, i) => x);
const z3 = nested.reduce((a, b) => a.concat(b), [1]);
const z4 = [1].concat(maybe);
const z5 = [].concat.apply([], ...nested);
const Pascal = nested;
const z6 = Pascal.flatMap(x => x);
const objectish: any = {};
const z7 = objectish.flatMap((x: number) => x);
