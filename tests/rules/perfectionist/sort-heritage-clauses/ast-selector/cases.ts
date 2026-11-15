interface A { a: 1 }
interface B { b: 1 }
interface I1 extends B, A {}
interface I2 extends A, B {}
class K1 implements A, B { a = 1 as const; b = 1 as const }
class K2 implements B, A { a = 1 as const; b = 1 as const }
