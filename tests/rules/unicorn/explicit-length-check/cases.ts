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

// 79.0.0: `<= 0` and `0 >=`, guards, shapes, known non-counts, global `Boolean`, parentheses.
declare const items: string[];
declare const box: { width: number; length: number };
if (items.length <= 0) {}
if (0 >= items.length) {}
const g1 = items.length > 0 && items.length;
const g2 = box.width && box.length;
const plain = { length: -1 };
if (plain.length) {}
const counted = { size: 2 };
if (counted.size) {}
const accessor = { get length() { return 1; } };
if (accessor.length) {}
if (Boolean(items.length)) {}
export function shadow(Boolean: (x: unknown) => boolean) {
  if (Boolean(items.length)) {}
}
const g3 = `${!items.length}`;
const g4 = (!items.length).toString();
const g5 = typeof !items.length;
if (items./* keep */length) {}
if (items.length as number) {}
let g6 = 1
!items.length ? 1 : 2;
