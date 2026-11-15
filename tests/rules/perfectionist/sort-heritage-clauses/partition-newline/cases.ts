interface A { a: 1 }
interface B { b: 1 }
interface C { c: 1 }
interface D { d: 1 }
interface I1 extends
  D,
  C,

  B,
  A {}
interface I2 extends D, C, B {}
