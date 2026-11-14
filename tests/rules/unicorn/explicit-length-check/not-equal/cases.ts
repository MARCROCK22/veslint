// unicorn/explicit-length-check with non-zero: not-equal.
declare const list: number[];

if (list.length) {}
const n1 = list.length > 0;
const n2 = list.length !== 0;
