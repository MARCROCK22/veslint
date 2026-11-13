// unicorn/no-nested-ternary: a conditional may hold one more, in parentheses, and no deeper.
declare let a: boolean, b: boolean, c: boolean, d: boolean;

// One level, without parentheses: reported, with the fix.
const x1 = a ? b : c ? 1 : 2;
const x2 = a ? b ? 1 : 2 : 3;
const x3 = a ? 1 : b ? 2 : c ? 3 : 4;
// Two levels or more: reported, without a fix.
const x4 = a ? (b ? (c ? 1 : 2) : 3) : 4;
const x5 = a ? (b ? (c ? (d ? 1 : 2) : 3) : 4) : 5;
const x6 = a ? 1 : (b ? 2 : (c ? 3 : 4));

// TypeScript: an assertion between them stops the nesting.
const x7 = a ? ((b ? 1 : 2) as number) : 3;
const x8 = a ? (b ? 1 : 2)! : 3;

// Not reported.
const z1 = a ? 1 : 2;
const z2 = a ? (b ? 1 : 2) : 3;
const z3 = a ? 1 : (b ? 2 : 3);
const z4 = (a ? b : c) ? 1 : 2;
const z5 = a ? [b ? 1 : 2] : 3;
