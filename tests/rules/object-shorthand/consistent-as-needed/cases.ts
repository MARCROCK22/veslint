declare const a: number;
declare const b: number;

// Reported with "consistent-as-needed".
const o1 = { a: a, b: b };
const o2 = { a: a, f: function () {} };
const o3 = { a, b: b };

// Not reported.
const k1 = { a: a, b: 1 };
const k2 = { a, b };
