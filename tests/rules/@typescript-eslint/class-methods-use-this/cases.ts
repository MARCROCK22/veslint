interface I { m(): void }
declare class Base { m(): void; }

// Reported.
class A {
  m1() {}
  m2() { return 1; }
  get g() { return 1; }
  set s(v: number) {}
  #p() {}
  'quoted'() {}
  1() {}
  [Symbol.iterator]() {}
  f1 = () => {};
  f2 = function () {};
  accessor f3 = () => {};
  m3() { function inner(this: A) { return this; } return inner; }
  m4() { return function (this: A) { return this; }; }
  m5() { class X { y = this; } return X; }
}
const B = class { m() {} };
class C extends Base { override m() {} }
class D implements I { m() {} private n() {} protected o() {} public p() {} }

// Not reported.
class E extends Base {
  constructor() { super(); }
  static s() {}
  m1() { return this; }
  m2() { return () => this; }
  m3() { super.m(); }
  f1 = () => this;
  f2 = this.f1;
  static f3 = () => {};
  [this.toString()]: number;
  static { const z = 1; }
}
abstract class F { abstract m(): void; }
export { A, B, C, D, E, F };
