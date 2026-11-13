declare let x: any;

// Reported (TypeScript reports most of them too).
class A {}
// @ts-expect-error
A = 0;
class B {
  m() {
    // @ts-expect-error
    B = 0;
  }
}
let C = class D {
  m() {
    // @ts-expect-error
    D = 0;
  }
};
class E {}
// @ts-expect-error
({ E } = x);

// Not reported.
class F {}
let f = F;
