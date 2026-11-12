declare class Base<T> { a?: T }
declare class A {}
declare namespace B { class C {} }
declare class D<T> { d?: T }
// Reported with the option 'type', and fixed (not inside `declare global`).
interface I1 { a: string }
interface I2 {
  a: string;
  b(): void;
}
interface I3<T> { a: T }
interface I4<T extends object = {}> extends Base<T> { b: T }
interface I5 extends A, B.C, D<string> { a: string }
export interface I6 { a: string }
export default interface I7 { a: string }
declare interface I8 { a: string }
export declare interface I9 { a: string }
interface /* c1 */ I10 /* c2 */ extends /* c3 */ Base<string> /* c4 */ { c: string }
interface I11 {}
interface I12
{
  a: string;
}
declare global {
  interface Window {
    t3: string;
  }
  namespace Inner {
    interface I13 {
      a: string;
    }
  }
}
declare module 'mod' {
  interface I14 {
    a: string;
  }
  global {
    interface I15 {
      a: string;
    }
  }
}
namespace N1 {
  export interface I16 {
    a: string;
  }
}

// Not reported.
type T1 = { a: string };
