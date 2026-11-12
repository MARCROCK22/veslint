// The index is a constant expression: `**` and Math.pow are evaluated as V8 does. An exponent
// of 2 is `x * x` and one of 0.5 is `sqrt(x + 0)`, which the C library's pow does not always
// equal in the last bit; these bases are ones where it does not.
declare const list: string[];
declare function ok(x: string): boolean;

// Reported: the index is 0.
export const a1 = list.filter(ok)[Math.pow(2, 8) - 256];
export const a2 = list.filter(ok)[2 ** 0.5 - Math.pow(2, 0.5)];
export const a3 = list.filter(ok)[4.2193450670132844 ** 2 === 4.2193450670132844 * 4.2193450670132844 ? 0 : 1];
export const a4 = list.filter(ok)[Math.pow(5.8235941448747273, 2) - 5.8235941448747273 * 5.8235941448747273];
export const a5 = list.filter(ok)[1.516058350221015 ** 0.5 === 1.2312832128397653 ? 0 : 1];
export const a6 = list.filter(ok)[Math.pow(7.8664619727230782, 0.5) === 2.804721371673678 ? 0 : 1];
export const a7 = list.filter(ok)[(-0) ** 0.5];
export const a8 = list.filter(ok)[Math.pow(NaN, 0) - 1];
export const a9 = list.filter(ok)[Object.is(Math.pow(-Infinity, 0.5), Infinity) ? 0 : 1];

// Not reported: the index is not 0, or not a number that is one.
export const b1 = list.filter(ok)[Math.pow(2, 8)];
export const b2 = list.filter(ok)[Math.pow(1, Infinity)];
export const b3 = list.filter(ok)[(-1) ** -Infinity];
export const b4 = list.filter(ok)[Math.pow(1.1, 3) === 1.331 ? 0 : 1];
