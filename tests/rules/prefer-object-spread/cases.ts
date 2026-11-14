declare const a: any;
declare const b: any;

// Reported.
const o1 = Object.assign({}, a);
const o2 = Object.assign({}, a, b);
const o3 = Object.assign({ x: 1 }, a);
const o4 = Object.assign({});
const o5 = Object.assign({}, { y: 2 });
const o6 = Object.assign(({}), (a));
const o7 = Object.assign({}, a ? b : a);
Object.assign({}, a);
function f() {
  return Object.assign({}, a);
}

// Not reported.
const k1 = Object.assign(a, b);
const k2 = Object.assign({}, ...[a]);
const k3 = Object.assign({}, { get x() { return 1; } });

// A `__proto__` property in a source object is not reported (10.15.0).
const k4 = Object.assign({}, { __proto__: a });
const k5 = Object.assign({}, { ['__proto__']: a });
const k6 = Object.assign({}, a, { '__proto__'() {} });
const o8 = Object.assign({ __proto__: a }, b);
const o9 = Object.assign({}, { ...a, x: 1 });

// A `;` before the object when the statement would continue the line before (10.15.0).
a
Object.assign({}, b)
f()
Object.assign({}, b).toString()
a;
Object.assign({}, b)
