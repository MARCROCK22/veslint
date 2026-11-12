declare class Foo<T = unknown, U = unknown> {
  constructor(a?: T);
}
declare namespace ns {
  class Foo<T> {}
}
declare function dec(...args: unknown[]): any;
// Reported with the default option ('constructor'), and fixed.
const a1: Foo<string> = new Foo();
const a2: Foo<string> = new Foo;
const a3: Foo<string, number> = new Foo();
let a4: Foo<string> = new Foo(), a5: Foo<number> = new Foo();
const a6: /* c1 */ Foo /* c2 */ <string> /* c3 */ = /* c4 */ new Foo();
const a7: Foo<
  string // inner
> = new Foo();
const a8: (Foo<string>) = new Foo();
const a9: Foo<string> = (new Foo());
const a10: Foo<string> = new (Foo)();
const a11: Map<string, number> = new Map();
const a12 : Foo<string>=new Foo ( );
class C1 {
  p1: Foo<string> = new Foo();
  static p2: Foo<string> = new Foo();
  accessor p3: Foo<string> = new Foo();
  @dec p4: Foo<string> = new Foo();
  private p5?: Foo<string> = new Foo();
  p6!: Foo<string> = new Foo();
  ['computed']: Foo<string> = new Foo();
  #private: Foo<string> = new Foo();
  declare p7: Foo<string>;
  constructor(a: Foo<string> = new Foo()) {}
  method(a: Foo<string> = new Foo(), b?: Foo<number> = new Foo(), @dec c: Foo<boolean> = new Foo()) {}
}
function f1(a: Foo<string> = new Foo()) {}
function* f2(a: Foo<string> = new Foo()) {}
const f3 = function (a: Foo<string> = new Foo()) {};
const o1 = { m(a: Foo<string> = new Foo()) {}, set s(a: Foo<string>) {} };
for (const x: Foo<string> = new Foo(); ; ) {
  break;
}
namespace Shadow {
  declare class Int8Array<T> {}
  const s1: Int8Array<string> = new Int8Array();
}

// Not reported.
const b1 = new Foo<string>();
const b2: Foo<string> = new Foo<string>();
const b3: Foo = new Foo();
const b4: Map<string, number> = new Foo();
const b5: Foo<string> = Foo();
const b6: ns.Foo<string> = new ns.Foo();
const b7: Foo<string> = new ns.Foo();
const b8 = (a: Foo<string> = new Foo()) => a;
class C2 {
  constructor(private a: Foo<string> = new Foo(), readonly b: Foo<string> = new Foo()) {}
  m?(a: Foo<string>): void;
}
declare function f4(a: Foo<string>): void;
const b9: Uint8Array<ArrayBuffer> = new Uint8Array();
const b10: Float32Array<ArrayBufferLike> = new Float32Array();
const b11: Foo<string> = new Foo<number>();
let b12: Foo<string>;
const b13: Foo<string> | null = new Foo();
export {};
