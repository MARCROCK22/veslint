// unicorn/prefer-array-some: `.some()` instead of `.find()`, `.findIndex()` and `.filter().length`.
declare const list: number[];

if (list.find(x => x > 1)) {}
const s1 = !list.findLast(x => x > 1);
const s2 = Boolean(list.find(x => x > 1));
const s3 = list.find(x => x > 1) ? 1 : 2;
const s4 = list.find(x => x > 1) !== undefined;
const s5 = list.find(x => x > 1) == null;
const s6 = (list.find(x => x > 1)) === undefined;
const s7 = list.findIndex(x => x > 1) !== -1;
const s8 = list.findLastIndex(x => x > 1) === -1;
const s9 = list.findIndex(x => x > 1) >= 0;
const s10 = list.findIndex(x => x > 1) < 0;
const s11 = list.filter(x => x > 1).length > 0;
const s12 = (list.filter(x => x > 1)).length !== 0;
while (list.find(x => x) && list.length) {}

// Not reported.
const z1 = list.find(x => x > 1);
const z2 = undefined !== list.find(x => x > 1);
const z3 = list.findIndex(x => x > 1) !== 0;
const z4 = list.filter(x => x > 1).length >= 1;
const z5 = list.filter(undefined).length > 0;
const z6 = list.find(x => x) ?? 1;
