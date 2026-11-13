declare const a: number;

// Reported with "never".
const o1 = { a };
const o2 = { f() {} };
const o3 = { async g() {} };
const o4 = { *h() {} };
const o5 = { async *i() {} };
const o6 = { ['k']() {} };
const o7 = { 'l'() {} };

// Not reported.
const k1 = { a: a };
const k2 = { get g() { return 1; } };
