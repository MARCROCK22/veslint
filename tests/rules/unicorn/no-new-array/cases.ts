// unicorn/no-new-array: `new Array(x)` is unclear.
declare const size: number;
declare const items: string[];
declare let unknown: unknown;
const length = 3;

const a1 = new Array(10);
const a2 = new Array(size.valueOf() + 1);
const a3 = new Array('a');
const a4 = new Array(unknown);
const a5 = new Array(...items);
const a6 = new Array(length);
const a7 = new Array((size, 2));
let a8;
a8 = 1
new Array(unknown)
const a9 = new Array(1n);

// Not reported.
const z1 = new Array();
const z2 = new Array(1, 2);
const z3 = Array(1);
