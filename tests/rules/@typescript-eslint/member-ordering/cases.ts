declare function dec(...args: unknown[]): any;
// Reported with the default order.
class A {
  method() {}
  field = 1;
  static s = 2;
  constructor() {}
  private p = 3;
  #h = 4;
  get g() {
    return 1;
  }
  [key: string]: unknown;
  static {}
  @dec decorated = 5;
  accessor acc = 6;
  arrow = () => 1;
}
abstract class B {
  abstract m(): void;
  abstract f: number;
  protected abstract accessor a: number;
  readonly r = 1;
  readonly [k: number]: number;
}
interface I {
  m(): void;
  f: string;
  new (): I;
  (): void;
  [k: string]: unknown;
}
type T = {
  m(): void;
  readonly f: string;
};
const C = class {
  m() {}
  f = 1;
};
class Overloads {
  m(): void;
  m(a?: number): void {}
  f = 1;
}
// Not reported.
class D {
  [key: string]: unknown;
  static s = 1;
  @dec decorated = 2;
  f = 3;
  static {}
  constructor() {}
  accessor acc = 4;
  get g() {
    return 1;
  }
  set g(v) {}
  m() {}
}
