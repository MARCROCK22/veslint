declare const a: any;
declare const b: any;

// Reported with enforceForLogicalOperands.
if (a && !!b) {}
if (!!a || Boolean(b)) {}
while ((!!a && b) || a) {}

// Not reported.
const k1 = a || !!b;
if (a ?? !!b) {}
