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

// 79.0.0: `length - 1` is fixed, larger offsets are suggestions; `with` is gone; wrappers,
// comments, safe integers.
const n1 = list.slice(list.length - 1);
const n2 = list.slice(list.length - 2);
const n3 = list.at((list.length as number) - 1);
const n4 = list.at(list.length - (1 as number));
const n5 = list.with(list.length - 1, 0);
const n6 = list.slice(list./* keep */length - 1);
const n7 = list.slice(list.length - 1.5);
const n8 = list.slice(list.length - 2 ** 60);
const n9 = Array.prototype.slice.call(list, list.length - 1);
const n10 = [].slice.apply(list, [list.length - 3]);
const n11 = ``.slice.call(text, text.length - 1);
const n12 = list.slice(list.length -   1);
