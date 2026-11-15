interface a { a: 1 }
interface B { b: 1 }
interface I1 extends a, B {}
interface I2 extends B, a {}
