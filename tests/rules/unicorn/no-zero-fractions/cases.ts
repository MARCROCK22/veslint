// unicorn/no-zero-fractions: no zero fraction (`1.0`) and no dangling dot (`1.`) in a number.
declare let n: number;

const a1 = 1.0;
const a2 = 1.50;
const a3 = 1.;
const a4 = 0.0;
const a5 = .0;
const a6 = 1.0e10;
const a7 = 1_000.000_0;
const a8 = 2.00 + 1;
const a9 = 1.0.toFixed(2);
const a10 = (1.0).toFixed(2);
const a11 = 1.5e0.toFixed(1);
function f() {
  return.0;
}
let y = 1
1.0.toString()

// Not reported.
const z1 = 1;
const z2 = 1.5;
const z3 = 1e10;
const z4 = 0x10;
const z5 = 1_0.5_1;

// 79.0.0: a leading zero before the decimal point.
export const leadingZero1 = .5;
export const leadingZero2 = -.5;
export const leadingZero3 = .5e2;
export const leadingZero4 = .5.toString();
export const leadingZero5 = .0;
export const leadingZero6 = .10;
export function leadingZero7() {return.5}
