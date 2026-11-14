// unicorn/prefer-math-trunc: `Math.trunc()` instead of bitwise operators with 0 and `~~`.
declare let n: number;
declare const box: { value: number; next(): { value: number } };

const t1 = n | 0;
const t2 = n >> 0;
const t3 = n << 0;
const t4 = n ^ 0;
const t5 = ~~n;
const t6 = ~~~n;
const t7 = (n, n) | 0;
n |= 0;
n >>= 0;
box.value ^= 0;
box.next().value |= 0;
function f() {
  return~~n;
}

// Not reported.
const z1 = n | 1;
const z2 = n & 0;
const z3 = n >>> 0;
const z4 = ~n;

// 79.0.0: every form is a suggestion, kept away when a comment would be lost; parseInt of
// String(…) with a radix of 10.
declare const num: number;
const t1 = parseInt(String(num), 10);
const t2 = Number.parseInt(String(num /* keep */), 10);
const t3 = parseInt(String(num), /* lost */ 10);
const t4 = parseInt(String(num), 16);
const t5 = (num /* keep */) | 0;
const t6 = num | /* lost */ 0;
const t7 = ~~(/* keep */ num);
const t8 = ~/* lost */~num;
const t9 = ((num)) | 0;
function shadow(parseInt: (s: string, r: number) => number) {
  return parseInt(String(num), 10);
}
