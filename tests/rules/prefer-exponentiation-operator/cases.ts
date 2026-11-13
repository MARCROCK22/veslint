declare const a: number;
declare const b: number;

// Reported.
const x1 = Math.pow(a, b);
const x2 = Math.pow(a + 1, b);
const x3 = Math.pow(a, b + 1);
const x4 = Math.pow(-a, b);
const x5 = 2 * Math.pow(a, b);
const x6 = -Math.pow(a, b);
const x7 = Math.pow(a, b) ** 2;
const x8 = 2 ** Math.pow(a, b);
const x9 = Math['pow'](a, b);
const m = Math;
const x10 = m.pow(a, b);
const { pow } = Math;
const x11 = pow(a, b);
const x12 = globalThis.Math.pow(a, b);
const x13 = Math.pow(a /* c */, b);
const x14 = Math.pow(...[a, b]);
const x15 = Math.pow(a);
Math.pow(a, b);
const x16 = a+Math.pow(-b, 2);
const x17 = (Math.pow(a, b));

// Not reported.
const k1 = a ** b;
const k2 = Math.max(a, b);
function shadow(Math: { pow(a: number, b: number): number }) {
  return Math.pow(a, b);
}
