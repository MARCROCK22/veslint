// unicorn/prefer-negative-index: `.length - n` where a negative index works.
declare const list: number[];
declare const text: string;
declare const bytes: Uint8Array;

const n1 = list.slice(list.length - 2, list.length - 1);
const n2 = text.slice(text.length - 1);
const n3 = bytes.subarray(bytes.length - 3);
const n4 = list.at(list.length - 1);
const n5 = list.with(list.length - 1, 0);
const n6 = list.toSpliced(list.length - 1, 1);
list.splice(list.length - 1, 1);
const n7 = Array.prototype.slice.call(list, list.length - 2);
const n8 = [].slice.apply(list, [list.length - 2]);
const n9 = ''.slice.call(text, text.length - 4);
const n10 = list.slice((list.length) - 2 - 1);
const n11 = list.at(( list.length ) - 1);

// Not reported.
const z1 = list.slice(text.length - 1);
const z2 = list.at(list.length + 1);
const z3 = list.at(list.length - 0);
const z4 = list.splice(0, list.length - 1);
