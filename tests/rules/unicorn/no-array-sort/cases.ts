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
