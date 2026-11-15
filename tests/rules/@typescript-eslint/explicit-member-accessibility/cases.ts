declare function dec(...args: unknown[]): any;
// Reported with suggestions: no accessibility.
class A {
  x = 1;
  static y: number;
  readonly z = 2;
  declare d: string;
  accessor acc = 1;
  constructor(readonly r: number, override o = 1) {}
  method() {}
  static staticMethod() {}
  get g() {
    return 1;
  }
  set g(v) {}
  async *gen() {}
  ['computed']() {}
  [`template`] = 1;
  [Symbol.iterator]() {}
  'quoted-name'() {}
  'valid'() {}
  123() {}
  1e3 = 1;
  0x10n = 2;
  [/re/gi]() {}
  [null] = 1;
  [true] = 2;
  [a.b[0]] = 3;
  ünï = 1;
  abc = 2;
  @dec x2 = 1;
  @dec() @dec method2() {}
  @dec
  method3() {}
  #priv = 1;
  #privMethod() {}
}
class P {
  constructor(@dec readonly ñame: string, readonly b = 1) {}
}
abstract class B {
  abstract x: number;
  abstract m(): void;
  abstract accessor a: number;
  abstract get g(): number;
}
// Not reported.
class C {
  public x = 1;
  private y = 2;
  protected z = 3;
  public constructor(private a: number, protected b: number, public c: number) {}
  public m() {}
  private static s() {}
}
const o = { m() {}, x: 1 };
interface I {
  m(): void;
  x: number;
}
