export class A {
  a = 1;
  b = 2;

  c = 3;
  m() {}
  n() {
    return 1;
  }
  static s = 4; // comment
  // leading comment
  o() {}
  /* block */ p() {}

  q() {} /* trailing */


  r() {}
  x = 1
  ;[k] = 2
  y = 3;
  static {
    this.y;
  }
  get g() { return 1; }
  set g(v: number) {}
  [key: string]: unknown;
  accessor acc = 1;
  declare d: number;
  constructor() {}
}

export abstract class B {
  f(): void;
  f(x?: number): void {}
  g(): void;

  g(x?: number): void {}
  abstract h(): void;
  abstract i(): void;
  abstract j: number;
  k = 1;
}

export class C { a = 1; b = 2; m() {} n() {} }

export class D {
  a = 1;
  b = 2;
  m() {
    class Inner {
      x = 1;
      y() {}
    }
    return Inner;
  }
  n() {}
}

const E = class {
  a = 1; // one
  // two

  b = 2;
};
export { E };

export class F {
  a = 1; /* a
  b */ b = 2;
  c = 1; /* c */ /* d */


  e = 2;
}
