interface BaseA { a: 1 }
interface BaseB { b: 1 }
interface X { x: 1 }
interface Y { y: 1 }
interface I1 extends X, BaseB, Y, BaseA {}
interface I2 extends BaseA, BaseB, X, Y {}
class K implements Y, BaseA { a = 1 as const; y = 1 as const }
