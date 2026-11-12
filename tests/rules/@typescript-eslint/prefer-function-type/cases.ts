declare class Base {}
// Reported, and fixed.
interface I1 { (): void }
interface I2 { (a: string): number; }
interface I3 { new (): I3 }
interface I4<T> { (a: T): T }
interface I5<T extends string = 'a'> { (a: T): T; }
interface I6 extends Function { (): void }
export interface I7 { (): void }
declare interface I8 { (): void }
export declare interface I9 { (): void }
interface I10 {
  // comment before
  (): void; // comment after
}
interface I11 {
  /* block before */ (): void /* block after */
}
export interface I12 {
  // before
  (): string; // after
}
interface I13 {
  (): void,
}
interface I14 { (): (this: I14) => void }
interface I15 { (): { a: this } }
interface I16 { (): { [K in 'a']: string } }
type T1 = { (): void };
type T2 = { (a: string): void } | string;
type T3 = { (): void } & { a: string };
type T4 = { (): void }[];
type T5 = ({ (): void })[];
type T6 = { new (): T6 };
type T7 = { (): void; };
type T8 = {
  // comment
  (): void
};
let v1: { (): void };
function f1(cb: { (): void }) {}
type T9 = Array<{ (): void }>;
type T10 = { (): void } extends string ? 1 : 2;
type T11 = { (a: string): asserts a is 'x' };
// Reported at the `this` type, not fixed.
interface I17 { (): this }
interface I18 { (): this is string }
interface I19 { (a: this): void }
interface I20 { (): asserts this }
interface I21 { (): [this, this] }
interface I22 { (): { [K in keyof this]: string } }
// Reported, not fixed: export default.
export default interface I23 { (): void }

// Not reported.
interface I24 { (): void; a: string }
interface I25 extends Base { (): void }
interface I26 extends Function, Base { (): void }
interface I27 { () }
interface I28 { a(): void }
interface I29 {}
type T12 = { a: string };
type T13 = { [K in 'a']: () => void };
type T14 = { (): void; (a: string): void };
