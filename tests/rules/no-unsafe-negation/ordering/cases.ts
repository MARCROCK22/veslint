declare const a: any;
declare const b: any;

// Reported with enforceForOrderingRelations.
if (!a < b) {}
if (!a > b) {}
if (!a <= b) {}
if (!a >= b) {}
const x = !a in b;
foo(!a < b);

// Not reported.
if ((!a) < b) {}
if (!(a < b)) {}
if (!a == b) {}
if (!a === b) {}
if (a < !b) {}
declare function foo(x: boolean): void;
