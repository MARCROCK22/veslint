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

// 79.0.0: `globalThis.Array` and the like; parentheses where `===` binds more loosely and around a
// left operand that binds more loosely than `typeof`; no fix that would lose comments.
declare const v: unknown, w: number;
const g1 = v instanceof globalThis.Array;
const g2 = v instanceof window.Function;
const g3 = !(v instanceof Function);
const g4 = (v as any) + w instanceof Function;
const g5 = true === v instanceof Function;
const g6 = v instanceof /* lost */ Array;
const g7 = (v /* kept */) instanceof Array;
const g8 = v instanceof String /* lost */;
const g9 = (v instanceof Function).toString();
declare function call(): void;
call()
v instanceof Function ? 1 : 2;
