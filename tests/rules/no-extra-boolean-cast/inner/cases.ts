declare const a: any;
declare const b: any;

// Reported with enforceForInnerExpressions.
if (a ? !!b : Boolean(a)) {}
if (a ?? !!b) {}
if ((a, !!b)) {}
if (a || !!b) {}

// Not reported.
const k1 = a ? !!b : a;
if (!!a ?? b) {}
