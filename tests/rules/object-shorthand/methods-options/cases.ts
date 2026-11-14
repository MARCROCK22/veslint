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

// ignoreConstructors takes the static name of any key, and needs a letter (10.15.0).
const c1 = { 'Ctor': function () {} };
const c2 = { ['Ctor']: function () {} };
const c3 = { [`Ctor`]: function () {} };
declare const Y: string;
const c4 = { [Y]: function () {} };
const c5 = { _1: function () {} };
const c6 = { $Ñandu: function () {} };
const c7 = { $ñandu: function () {} };
const c8 = { _ㄱ: function () {} };
const c9 = { _Ⅰ: function () {} };
