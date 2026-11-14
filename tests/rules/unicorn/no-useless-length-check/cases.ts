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
