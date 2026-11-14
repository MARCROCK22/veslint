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

// 79.0.0: every built-in error, Intl and WebAssembly constructors, optional chains, and the
// namespaces that are neither functions nor constructors.
const n1 = TypeError('x');
const n2 = AggregateError([]);
const n3 = Intl.DateTimeFormat();
const n4 = Intl.NumberFormat('en');
const n5 = Intl?.DateTimeFormat();
const n6 = Array?.(3);
const n7 = WebAssembly.Memory({ initial: 1 });
// @ts-expect-error -- not callable
const n8 = WebAssembly();
// @ts-expect-error -- not a constructor
const n9 = new WebAssembly();
// @ts-expect-error -- not a constructor
const n10 = new WebAssembly.JSTag();
const n11 = new (Intl.Collator)();
const n12 = globalThis.Intl.Segmenter();
export function newOnNextLine() {
  return new
    String('x');
}
const n13 = new (new Boolean(1).constructor)();
let n14 = 1
new String('x').length;
