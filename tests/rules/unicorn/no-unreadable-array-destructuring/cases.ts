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
