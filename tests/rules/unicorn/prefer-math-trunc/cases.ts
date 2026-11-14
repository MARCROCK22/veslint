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
