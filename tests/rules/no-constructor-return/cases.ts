// Reported.
class A {
  constructor(a: number) {
    if (a) {
      return {} as A;
    }
    return this;
  }
}
// Not reported.
class B {
  constructor() {
    const f = () => {
      return 1;
    };
    function g() {
      return 2;
    }
    f();
    g();
    return;
  }
  method() {
    return 1;
  }
}
const o = {
  constructor() {
    return 1;
  },
};
export { A, B, o };
