interface _B { a: 1 }
interface A { b: 1 }
interface $C { c: 1 }
interface I1 extends _B, A, $C {}
interface I2 extends A, _B, $C {}
