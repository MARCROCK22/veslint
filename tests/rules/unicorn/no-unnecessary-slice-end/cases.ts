// unicorn/no-unnecessary-slice-end: `.length` or `Infinity` as the end of `.slice()`.
declare const list: number[];
declare const text: string;

const s1 = list.slice(1, list.length);
const s2 = text.slice(0, text.length);
const s3 = list.slice(1, Infinity);
const s4 = list.slice(1, Number.POSITIVE_INFINITY,);
const s5 = list.slice(1, (list.length));

// Not reported.
const z1 = list.slice(1);
const z2 = list.slice(1, text.length);
const z3 = list.slice(list.length);
