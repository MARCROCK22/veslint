// unicorn/new-for-builtins: built-ins that construct objects are called with `new`; the primitive
// wrappers without it. `Date()` is a string: `String(new Date())`.
declare const value: unknown;

const e1 = Map();
const e2 = Array(3);
const e3 = globalThis.Set([1]);
const e4 = window.Promise.resolve === undefined ? WeakMap() : null;
const e5 = Uint8Array([1]);
const e6 = Object(value);
const e7 = Date();
const e8 = Date(1);
const e9 = Date(/* now */);
const MyMap = Map;
const e10 = MyMap();
function f() {
  return(Error)('x');
}
const d1 = new String('x');
const d2 = new Boolean(value);
const d3 = new Number(1);
const d4 = new BigInt(1);
const d5 = new Symbol('x');
const d6 = new Symbol;
const d7 = new globalThis.BigInt(1);

// Not reported.
const z1 = Object(value) === value;
const z2 = value !== Object(value);
const z3 = new Map();
const z4 = String(value);
function shadowed(Map: MapConstructor) {
  return Map();
}
