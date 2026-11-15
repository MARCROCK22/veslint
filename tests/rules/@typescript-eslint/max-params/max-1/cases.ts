function f1(a: number, b: number, c: number) { return a + b + c; }
function f2(a: number, b: number, c: number, d: number) { return a + b + c + d; }
function f3(this: void, a: number, b: number, c: number) { return a + b + c; }
function f4(this: Window, a: number, b: number, c: number) { return [this, a, b, c]; }
const f5 = (a: number, b: number, c: number, d: number) => a + b + c + d;
const f6 = async (a: number, b: number, c: number, d: number): Promise<number> => a + b + c + d;
const f7 = function* (a: number, b: number, c: number, d: number) { yield a + b + c + d; };
declare function f8(a: number, b: number, c: number, d: number): void;
type T1 = (a: number, b: number, c: number, d: number) => void;
type T2 = <X>(a: X, b: X, c: X, d: X) => (e: X, f: X, g: X, h: X) => X;
type T3 = new (a: number, b: number, c: number, d: number) => object;
interface I { m(a: number, b: number, c: number, d: number): void; p: (a: number, b: number, c: number, d: number) => void }
class C {
  constructor(a: number, b: number, c: number, d: number) { void [a, b, c, d]; }
  m(a: number, b: number, c: number, d: number) { return a + b + c + d; }
  static async #p(a: number, b: number, c: number, d: number) { return a + b + c + d; }
  q = (a: number, b: number, c: number, d: number) => a + b + c + d;
  r(a: number, b: number, c: number, d: number): void;
  r() {}
  ['s'](a: number, b: number, c: number, d: number) { return a + b + c + d; }
  static t(this: void, a: number, b: number, c: number) { return a + b + c; }
}
const o = { m(a: number, b: number, c: number, d: number) { return a + b + c + d; }, get g() { return 1; } };
export { f1, f2, f3, f4, f5, f6, f7, f8, type T1, type T2, type T3, type I, C, o };
