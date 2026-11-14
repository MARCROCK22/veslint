// unicorn/no-useless-length-check: a length check `.some()` or `.every()` makes useless.
declare const list: number[];
declare const other: number[];

const u1 = list.length === 0 || list.every(Boolean);
const u2 = list.length > 0 && list.some(Boolean);
const u3 = list.some(Boolean) && list.length !== 0;
const u4 = list.every(x => x) || list.length === 0 || other.length > 0;
const u5 = (list.length > 0) && (list.some(Boolean));
const u6 = other.length > 0 && list.length > 0 && list.some(Boolean);

// Not reported.
const z1 = list.length === 0 && list.every(Boolean);
const z2 = list.length > 0 || list.some(Boolean);
const z3 = other.length > 0 && list.some(Boolean);
const z4 = list.length >= 1 && list.some(Boolean);
const z5 = list.length > 0 && list?.some(Boolean);

// 79.0.0: `for…of` guards, suggestions for unsafe removals, comments, known non-arrays.
declare function use(x: number): void;
declare function check(x: number): boolean;
declare const set: Set<number> & { some(cb: (x: number) => boolean): boolean; length: number };
if (list.length > 0) {
  for (const item of list) {
    use(item);
  }
}
if (list.length !== 0) for (const item of list) use(item);
if (list.length > 0) {
  // keep
  for (const item of list) use(item);
}
if (list.length > 0) for await (const item of list) use(item);
if (list.length > 0) {
  for (const item of list) use(item);
} else {
  use(0);
}
const u1 = list.length > 0 && list.some(check);
const u2 = list.some(x => x > 0) && list.length > 0;
const u3 = list.some(check) && list.length > 0;
const u4 = list.length === 0 || list.every(x => { use(x); return true; });
const u5 = list.length /* keep */ > 0 && list.some(check);
const u6 = set.length > 0 && set.some(check);
const u7 = list.length > 0 && list.some(check) && other.length > 0;
let u8 = 1
list.length > 0 && list.some(check);
if (list.length > 0) {
  for (const item of list) {
    use(`a
b`.length + item);
  }
}
