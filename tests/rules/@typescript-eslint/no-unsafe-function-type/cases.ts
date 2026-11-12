// no-unsafe-function-type: the global `Function` as the name of a type reference, of an
// `implements` or of an interface's `extends`; not a name the file declares, nor a declaration.
let a: Function;
let b: Function | null;
let c: Array<Function>;
let d: { f: Function };
let e: (callback: Function) => void;
type F = Function;
function g<T extends Function>(t: T): T {
  return t;
}
class H implements Function {}
interface I extends Function {}
let j = a as Function;
let k: Function[];

// Not the global type.
namespace Shadowed {
  interface Function {}
  export let s: Function;
}
let q: Shadowed.Function;
let r: typeof Function;
let t = Function;

export { a, b, c, d, e, g, H, j, k, q, r, t };
export type { F, I };
