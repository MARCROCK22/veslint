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

// 79.0.0: only constants whose results do not change are fixed, the others are suggestions.
declare let xx: number, yy: number;
const m1 = Math.sqrt(xx * xx);
const m2 = Math.sqrt(3 * 3);
const m3 = Math.sqrt(0.1 * 0.1);
const m4 = Math.sqrt(xx ** 2 + yy ** 2);
const m5 = Math.sqrt(0 ** 2 + 0 ** 2);
const m6 = Math.sqrt(Infinity ** 2 + 2 ** 2);
const m7 = Math.log(xx) * Math.LOG10E;
const m8 = Math.log(1) * Math.LOG10E;
const m9 = Math.log(0) / Math.LN2;
const m10 = Math.log(-Infinity) / Math.LN10;
void Math.sqrt(xx * xx);
for (Math.sqrt(xx * xx); ; Math.log(xx) / Math.LN2) break;
const three = 3;
const m11 = Math.sqrt(three * three);
const m12 = Math.sqrt(Number.MAX_SAFE_INTEGER ** 2);
const m13 = Math.log(/* keep */ xx) * Math.LOG2E;
const m14 = Math.log(xx) /* lost */ * Math.LOG2E;
const m15 = Math.sqrt(xx /* lost */ ** 2);
const m16 = Math.sqrt((xx as number) ** 2 + (yy!) ** 2);
