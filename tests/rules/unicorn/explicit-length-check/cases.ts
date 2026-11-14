// unicorn/explicit-length-check: compare `.length` and `.size` explicitly.
declare const list: number[];
declare const set: Set<number>;
declare function use(x: unknown): void;

if (list.length) {}
if (!list.length) {}
if (!!set.size) {}
const e1 = Boolean(list.length);
const e2 = list.length === 0 ? 1 : 2;
const e3 = list.length == 0;
const e4 = list.length < 1;
const e5 = list.length != 0;
const e6 = list.length >= 1;
const e7 = 0 === list.length;
const e8 = 1 > list.length;
const e9 = 0 < list.length;
const e10 = list.length && use(list);
while (set.size) {}
const e11 = !(list.length > 0);
async function f() {
  return !await list.length;
}
const e12 = !list.length == true;

// Not reported.
const z1 = list.length > 0;
const z2 = list.length === 0;
const z3 = list.length;
const z4 = 'abc'.length ? 1 : 2;
const z5 = list.length || 1;
