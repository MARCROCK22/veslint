/* global BigInt:off, Number:off */
// With `lib: ["es5"]` no lib declares BigInt, so turning the global off takes it away; Number is
// still declared by the lib.
declare const list: number[];
list.filter(x => x > 1)[BigInt(0) as unknown as number];
list.filter(x => x > 1)[Number('0')];
