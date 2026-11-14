declare const a: any;

// Reported with null "never".
if (a === null) {}
if (null !== a) {}
if (a == 1) {}

// Not reported.
if (a == null) {}

// Only `===` and `!==` with null are reported (10.15.0).
declare const n1: any;
if (n1 >= null) {}
const n2 = n1 + null;
if (n1 instanceof Object || null !== n1) {}
