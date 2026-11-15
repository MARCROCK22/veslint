// Reported: could be parameter properties.
class A {
  a: number;
  private b: string;
  readonly c;
  ñ: string;
  constructor(a: number, b: string, c, ñ: string) {
    this.a = a;
    this.b = b;
    this.c = c;
    this.ñ = ñ;
  }
}
class Nested {
  x: number;
  constructor(x: number) {
    this.x = x;
    const Inner = class {
      y: string;
      constructor(y: string) {
        this.y = y;
      }
    };
  }
}
class Overloads {
  x: number;
  constructor(x: number);
  constructor(x: number) {
    this.x = x;
  }
}
// Not reported.
class B {
  a: number;
  b: string = '';
  c: number;
  d: number;
  e: string;
  #f: number;
  ['g']: number;
  h: number;
  constructor(a: string, b: string, c: number, d: number, e: string, h: number) {
    this.a = a as any;
    this.b = b;
    console.log(c);
    this.c = c;
    this.d = d + 1;
    this.e = e;
    this.h = h;
  }
}
class C {
  a: number;
  constructor(a: number) {
    this.a = a;
  }
  method(a: number) {
    this.a = a;
  }
}
class D {
  a: number;
  constructor(public b: number) {}
}
class E {
  a: number;
  constructor(b: number) {
    this.a = b;
  }
}
