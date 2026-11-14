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

// A method with a `super` of its own stays a method; `__proto__` is left alone (10.15.0).
const s1 = { m() { return super.toString(); } };
const s2 = { m() { return () => super.toString(); } };
const s3 = { outer() { return { inner() { return super.valueOf(); } }; } };
const s4 = { outer() { return { [super.toString()]() {} }; } };
const s5 = { m() { class K { x = super.toString; } return K; } };
const s6 = { m() { return function () { return 1; }; } };
declare const __proto__: object;
const s7 = { __proto__ };
const s8 = { __proto__() {} };
