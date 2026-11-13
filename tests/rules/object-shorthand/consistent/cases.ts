declare const a: number;
declare const b: number;

// Reported with "consistent".
const o1 = { a, b: b };
const o2 = { a, f: function () {} };

// Not reported.
const k1 = { a, b };
const k2 = { a: a, b: b };
const k3 = { a, get g() { return 1; } };
