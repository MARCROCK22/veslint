interface BaseA { a: 1 }
interface X { x: 1 }
interface Zed { z: 1 }
interface I1 extends BaseA, X, Zed {}
interface I2 extends
  BaseA,

  X,

  Zed {}
interface I3 extends
  BaseA,


  X,
  Zed {}
interface I4 extends Zed, X,
  BaseA {}
