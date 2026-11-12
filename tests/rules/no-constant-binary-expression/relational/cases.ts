declare let a: any;

// Reported with checkRelationalComparisons.
const r1 = 1 < 2;
const r2 = 'a' >= 'b';
const r3 = -1 <= +2;
const r4 = `x` > null;
const r5 = undefined < ~1;
const r6 = (1) < (2);

// Not reported.
const k1 = a < 1;
const k2 = `${a}` < 1;
const k3 = -a < 1;
const k4 = !1 < 2;
