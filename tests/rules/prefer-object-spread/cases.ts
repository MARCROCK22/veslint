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
