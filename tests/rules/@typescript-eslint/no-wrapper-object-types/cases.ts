// no-wrapper-object-types: the global wrapper classes as the name of a type reference (fixed to the
// primitive), of an `implements` or of an interface's `extends` (not fixed); not names the file
// declares.
let a: String;
let b: Number | Boolean;
let c: Array<Object>;
let d: { s: Symbol; b: BigInt };
type E = Object;
function f<T extends String>(t: T): T {
  return t;
}
class G implements Object {}
interface H extends Number, String {}
let i = a as Boolean;
let j: String[];
let k: Map<Symbol, BigInt>;

// Not the global classes.
namespace Shadowed {
  interface String {}
  export let s: String;
}
let m: Shadowed.String;
let n: typeof String;
let o = new String('x');
let p: string;

export { a, b, c, d, f, G, i, j, k, m, n, o, p };
export type { E, H };
