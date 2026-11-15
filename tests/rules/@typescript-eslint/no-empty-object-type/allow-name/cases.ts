interface FooProps {}
interface I1 {}
interface I2 extends I1 {}
type BarProps = {};
type T1 = {};
type T2 = { a: {} };
let v: {} = 1;
export { v, type FooProps, type I2, type BarProps, type T1, type T2 };
