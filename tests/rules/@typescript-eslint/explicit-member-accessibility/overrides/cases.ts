class A {
  x = 1;
  public y = 2;
  constructor(a: number, readonly b: number, public readonly c: number) {}
  get g() {
    return 1;
  }
  public set g(v) {}
  method() {}
  public other() {}
}
class B {
  public constructor() {}
}
