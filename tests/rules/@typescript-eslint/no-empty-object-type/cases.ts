interface I1 {}
interface I2<T, U extends string = 'x'> {}
interface I3 extends I1 {}
interface I4<T> extends Array<T> {}
interface I5 extends I1, I2<number> {}
interface I6 { a: string }
export interface I7 {}
export default interface I8 {}
declare interface I9 {}
class C1 {}
interface C1 {}
interface I10 {}
interface I10 {}
interface I11<T> {}
interface I11<T> {}
namespace NS {
  export interface I12 {}
}
declare global {
  interface I13 {}
}
type T1 = {};
type T2 = {} & { a: string };
type T3 = { a: string } | {};
let v1: {} = 1;
function f(a: {}): {} { return a; }
type T4<T extends {} = {}> = T;
type T5 = Record<string, {}>;
type T6 = {
  // a comment
};
abstract class C2 {}
interface C2 {}
export { v1, f, type T1, type T2, type T3, type T4, type T5, type T6, type I1, type I3, type I4, type I5, type I6, type I9, C1, type I10, type I11, NS, C2 };
