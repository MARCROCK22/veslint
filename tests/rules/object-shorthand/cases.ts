declare const a: number;
declare const b: number;

// Reported with "always".
const o1 = { a: a };
const o2 = { 'b': b };
const o3 = { f: function () {} };
const o4 = { g: async function () {} };
const o5 = { h: function* () {} };
const o6 = { ['k']: function () {} };
const o7 = { m: function (x: number): number { return x; } };
const o8 = { /* c */ a: a };

// Not reported.
const k1 = { a };
const k2 = { f() {} };
const k3 = { f: function named() {} };
const k4 = { f: () => {} };
const k5 = { get g() { return 1; } };
const k6 = { a: b };
const k7 = { [a]: a };
const k8 = { a: /** @type {number} */ (a) };
const { c: c } = { c: 1 };

// A key `__proto__` that is not computed is left alone (10.15.0).
declare const __proto__: object;
const p1 = { __proto__: __proto__ };
const p2 = { '__proto__': function () {} };
const p3 = { ['__proto__']: function () {} };
