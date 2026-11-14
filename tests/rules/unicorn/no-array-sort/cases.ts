// unicorn/no-array-sort: `.toSorted()` instead of `.sort()`.
declare const list: number[];
declare const compare: (a: number, b: number) => number;

const s1 = list.sort();
const s2 = list.sort(compare);
const s3 = list.sort((a, b) => a - b);
const s4 = [...list].sort();
const s5 = list.sort(compare.bind(null));

// Not reported.
list.sort();
const z1 = list.sort(undefined);
const z2 = list.sort(compare, 1);
const z3 = list.sort(compare());

// 79.0.0: receivers known not to be arrays are left.
declare const set: Set<number>;
declare const typed: Float64Array;
const k1 = set.sort();
const k2 = typed.sort();
function rest(...items: number[]) { return items.sort(); }
const k3 = Object.keys({}).sort();
const k4 = [...new Set([1])].sort();
const k5 = [...list, /* keep */].sort();
