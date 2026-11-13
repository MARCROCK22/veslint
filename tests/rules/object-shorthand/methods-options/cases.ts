// Reported with "methods" and its options.
const o1 = { f: function () {} };
const o2 = { g: () => { return 1; } };
const o3 = { h: async (x: number) => { return x; } };
const o4 = { i: x => { return x; } };

// Not reported.
const k1 = { Foo: function () {} };
const k2 = { _Bar: function () {} };
const k3 = { ignoredMethod: function () {} };
const k4 = { j: () => 1 };
const k5 = { k: () => { return this; } };
const k6 = { a: k1 };
