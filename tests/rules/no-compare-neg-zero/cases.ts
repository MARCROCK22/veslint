// no-compare-neg-zero: a comparison with -0, which is equal to 0 for every operator.
declare const x: number;
declare const big: bigint;

// Every comparison operator.
if (x === -0) {}
if (-0 === x) {}
if (x == -0) {}
if (x !== -0) {}
if (x != -0) {}
if (x > -0) {}
if (x >= -0) {}
if (x < -0) {}
if (x <= -0) {}

// Parentheses, comments, and the other ways of writing zero.
if ((x) === (-0)) {}
if (x === -(0)) {}
if (x === -/* zero */ 0) {}
if (x === -0.0) {}
if (x === -0e0) {}
if (x === -0x0) {}
if (x === -.0) {}
if (x === -0.0_0) {}
const inTernary = x === -0 ? 'negative zero' : 'something else';
while (x !== -0) {}

// Not a comparison with -0: other values, BigInt, other operators, TypeScript's wrappers.
if (x === 0) {}
if (x === +0) {}
if (x === -1) {}
if (x === -0.5) {}
if (x === '-0' as unknown) {}
if (big === -0n) {}
const sum = x + -0;
const bits = x & -0;
const same = Object.is(x, -0);
if (x === (-0 as number)) {}
if (x === (-0 satisfies number)) {}
if (x === <number>-0) {}
if (x === -x) {}
if (x === - -0) {}
