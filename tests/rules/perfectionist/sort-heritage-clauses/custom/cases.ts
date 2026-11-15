interface A { a: 1 }
interface B { b: 1 }
interface C { c: 1 }
interface I1 extends A, B, C {}
interface I2 extends C, B, A {}
