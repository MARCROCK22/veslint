declare class Foo<T = unknown, U = unknown> {
  constructor(a?: T);
}
declare namespace ns {
  class Foo<T> {}
}
// Reported with the option 'type-annotation', and fixed.
const a1 = new Foo<string>();
const a2 = new Foo<string>;
let a3 = new Foo<string, number>('x'), a4 = new Foo<number>();
const a5 /* c */ = new Foo /* c2 */ <string> /* c3 */ ();
const a6 = (new Foo<string>());
const a7 = new (Foo)<string>();
class C1 {
  p1 = new Foo<string>();
  static p2 = new Foo<string>();
  accessor p3 = new Foo<string>();
  p4? = new Foo<string>();
  ['computed'] = new Foo<string>();
  [('parens')] = new Foo<string>();
  [1 + 2] = new Foo<string>();
  #private = new Foo<string>();
  'quoted' = new Foo<string>();
  42 = new Foo<string>();
  constructor(a = new Foo<string>()) {}
  method(a = new Foo<string>(), b?: Foo<number>) {}
}
function f1(a = new Foo<string>(), { b } = new Foo<string>(), [c] = new Foo<string>()) {}
const { d } = new Foo<string>();
const [e] = new Foo<string>();

// Not reported.
const b1: Foo<string> = new Foo<string>();
const b2: Foo<string> = new Foo();
const b3 = new Foo();
const b4 = (a = new Foo<string>()) => a;
const b5 = new ns.Foo<string>();
class C2 {
  constructor(private a = new Foo<string>()) {}
}
export {};
