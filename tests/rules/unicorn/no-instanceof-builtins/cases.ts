// unicorn/no-instanceof-builtins: `instanceof` is unreliable with built-ins. `Array` gets
// `Array.isArray`, `Function` a `typeof`, primitive wrappers a suggestion; with "strict"
// (strict/), the other built-ins too, and `Error` gets `Error.isError` with useErrorIsError.
declare const x: unknown;
declare const Element: Function;

const a1 = x instanceof Array;
const a2 = (x) instanceof (Array);
const a3 = typeof x === 'object' && x instanceof Array;
const f1 = x instanceof Function;
const p1 = x instanceof String;
const p2 = x instanceof Number;
const p3 = (x as object) instanceof BigInt;
const s1 = x instanceof Map;
const s2 = x instanceof Error;
const s3 = x instanceof Promise;
const s4 = x instanceof Element;
const s5 = x instanceof Uint8Array;
function g() {
  return!(x instanceof Array);
}

// Not reported.
const z1 = x instanceof Foo;
const z2 = x instanceof globalThis.Array;
class Foo {}
