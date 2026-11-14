// unicorn/no-unreadable-array-destructuring: consecutive ignored values.
declare const list: number[];
declare function get(): number[];

const [,, a1] = list;
const [,,, ...rest] = list;
const [,, b1] = get();
const [,, c1] = list as number[];
let d1;
[,, d1] = list;
const [x1,,, y1] = list;
function f([,, z]: number[]) {
  return z;
}
const [,, e1 = 1] = list;

// Not reported.
const [, ok1] = list;
const [ok2, , ok3] = list;

// 79.0.0: destructuring into object properties; no fix for a source that is not indexable, a
// rest of a typed array, an annotated pattern or a comment that would be lost.
declare const target: { a: number; b: number };
declare const set: Set<number>;
declare const typed: Int8Array;
declare const list2: number[];
[target.a] = list2;
[, target.b] = list2;
({ x: [target.a] } = { x: list2 });
const [, , u1] = set;
const [, , ...u2] = typed;
const [, , u3]: number[] = list2;
const [, , /* lost */ u4] = list2;
const [, , u5 /* kept */] = list2;
const [, , u6] = typed;
