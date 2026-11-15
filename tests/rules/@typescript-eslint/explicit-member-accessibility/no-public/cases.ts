declare function dec(...args: unknown[]): any;
// Reported and fixed: public.
class A {
  public x = 1;
  public static y: number;
  public /* comment */ z = 2;
  public // line
  w = 3;
  public constructor(public readonly r: number, public p: number, public readonly q = 1) {}
  public method() {}
  public get g() {
    return 1;
  }
  public set g(v) {}
  @dec public decorated() {}
  public accessor acc = 1;
  public public = 1;
  public 'quoted-name'() {}
  public
  newline() {}
}
abstract class B {
  public abstract x: number;
  public abstract m(): void;
}
// Not reported.
class C {
  x = 1;
  private y = 2;
  protected m() {}
  constructor(readonly a: number, private b: number) {}
}
