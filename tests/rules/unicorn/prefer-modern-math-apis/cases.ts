// unicorn/prefer-modern-math-apis: `Math.log10()`, `Math.log2()`, `Math.hypot()` and `Math.abs()`
// instead of their older forms.
declare const a: number, b: number, c: number;
declare const box: { x: number };

const l1 = Math.log(a) * Math.LOG10E;
const l2 = Math.LOG10E * Math.log(a);
const l3 = Math.log(a) * Math.LOG2E;
const l4 = Math.log(a) / Math.LN10;
const l5 = Math.log((a + b)) / Math.LN2;
const h1 = Math.sqrt(a * a + b * b);
const h2 = Math.sqrt(a ** 2 + b ** 2 + c ** 2);
const h3 = Math.sqrt((a ** 2) + (b ** 2 + c ** 2));
const h4 = Math.sqrt(a ** 2);
const h5 = Math.sqrt(box.x * box.x);
const h6 = Math.sqrt(a ** 2 + b * b);

// Not reported.
const z1 = Math.log(a) * Math.LN10;
const z2 = Math.sqrt(a * b);
const z3 = Math.sqrt(a ** 3);
const z4 = Math.sqrt(a ** 2 - b ** 2);
const z5 = Math?.sqrt(a ** 2);
const z6 = Math.log(a, b) / Math.LN10;
