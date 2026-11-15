interface A10 { a: 1 }
interface A2 { b: 1 }
interface A1 { c: 1 }
interface I1 extends A10, A2, A1 {}
interface I2 extends A1, A2, A10 {}
