// unicorn/no-unnecessary-array-splice-count: `.length` or `Infinity` as the count of `.splice()`.
declare const list: number[];
declare const box: { list: number[] };

list.splice(1, list.length);
list.splice(1, Infinity);
list.splice(1, Number.POSITIVE_INFINITY);
const s1 = list.toSpliced(0, list.length);
box.list.splice(0, box.list.length);
list.splice(0, list?.length);

// Not reported.
list.splice(1, list.length, 2);
list.splice(1, box.list.length);
list.splice(1, list.length - 1);
list.splice?.(1, list.length);

// 79.0.0: receivers known not to be arrays; no fix when the first argument writes the receiver.
declare const custom: { splice(a: number, b: number): void; length: number };
declare let mutable: number[];
declare const set: Set<number> & { splice(a: number, b: number): void; length: number };
custom.splice(0, custom.length);
set.splice(0, set.length);
mutable.splice(mutable = [], mutable.length);
list.splice(list.length--, list.length);
list.splice(0, Infinity);
