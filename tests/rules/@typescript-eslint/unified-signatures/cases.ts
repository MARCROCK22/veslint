declare class Foo {}
declare class Bar {}
// Functions of the program.
function f1(a: string): void;
function f1(a: number): void;
function f1(a: unknown): void {}

function f2(): void;
function f2(a: string): void;
function f2(a?: string): void {}

function f3(a: string): void;
function f3(a: string, ...rest: number[]): void;
function f3(...args: unknown[]): void {}

// Three overloads: the message names the line of the other one.
function f4(a: string): void;
function f4(a: number): void;
function f4(a: boolean): void;
function f4(a: unknown): void {}

export function f5(a: string): void;
export function f5(a: number): void;
export function f5(a: unknown): void {}

declare function f6(a: string): void;
declare function f6(a: number): void;

export declare function f7(a: string): void;
export declare function f7(a: number): void;

export default function (a: string): void;
export default function (a: number): void;
export default function (a: unknown): void {}

// Module blocks.
namespace N1 {
  export function g1(a: string): void;
  export function g1(a: number): void;
  export function g1(a: unknown): void {}
  function g2(): void;
  function g2(a: string): void;
  function g2(a?: string): void {}
  namespace N1b {
    function g1(a: string): void;
    function g1(a: number): void;
    function g1(a: unknown): void {}
  }
}
declare namespace N2.Inner {
  function g3(a: string): void;
  function g3(a: number): void;
}
declare module 'mod' {
  export function g4(a: string): void;
  export function g4(a: number): void;
  global {
    function g5(a: string): void;
    function g5(a: number): void;
  }
}
declare global {
  function g6(a: string): void;
  function g6(a: number): void;
}
// Not checked: a block, a class expression.
function outer() {
  function inner(a: string): void;
  function inner(a: number): void;
  function inner(a: unknown) {}
}
const C0 = class {
  m(a: string): void;
  m(a: number): void;
  m(a: unknown) {}
};

// Classes.
class C1<T> {
  m1(a: string): void;
  m1(a: number): void;
  m1(a: unknown) {}
  static m2(a: string): void;
  static m2(a: number): void;
  static m2(a: unknown) {}
  m2(a: string): void;
  m2(a: unknown) {}
  constructor(a: string);
  constructor(a: number);
  constructor(a: unknown) {}
  ['m3'](a: string): void;
  ['m3'](a: number): void;
  ['m3'](a: unknown) {}
  [Symbol.iterator](a: string): void;
  [Symbol.asyncIterator](a: number): void;
  [Symbol.iterator](a: unknown) {}
  [Symbol.asyncIterator](a: unknown) {}
  #p(a: string): void;
  #p(a: number): void;
  #p(a: unknown) {}
  'lit'(a: string): void;
  'lit'(a: number): void;
  'lit'(a: unknown) {}
  42(a: string): void;
  42(a: number): void;
  42(a: unknown) {}
  m4(a: T): void;
  m4(a: string): void;
  m4(a: unknown) {}
  m5<U>(a: U): void;
  m5<U>(a: string): void;
  m5(a: unknown) {}
  m6<U extends string>(a: U): void;
  m6<U extends number>(a: string): void;
  m6(a: unknown) {}
  m7<U extends Foo>(a: U): void;
  m7<U extends Bar>(a: string): void;
  m7(a: unknown) {}
  m8(this: void, a: string): void;
  m8(this: void, a: number): void;
  m8(a: unknown) {}
  m9(this: C1<T>, a: string): void;
  m9(a: string, b: number): void;
  m9(a: unknown, b?: unknown) {}
  m10(a: T[]): void;
  m10(a: string[]): void;
  m10(a: unknown) {}
  m11(a: keyof T): void;
  m11(a: readonly T[]): void;
  m11(a: unknown) {}
  m12(a: Array<T>): void;
  m12(a: Array<string>): void;
  m12(a: unknown) {}
  m13<U>(a: U): void;
  m13<V>(a: string): void;
  m13(a: unknown) {}
  m14?(a: string): void;
  m14?(a: number): void;
  public m15(a: string): void;
  private m15(a: number): void;
  m15(a: unknown) {}
}
abstract class C2 {
  abstract m(a: string): void;
  abstract m(a: number): void;
  abstract get g(): string;
  abstract set g(v: string);
  protected abstract n(): void;
  protected abstract n(a: string): void;
}
declare class C3 {
  m(a: string): void;
  m(a: number): void;
  constructor(a: string);
  constructor(a: string, b?: number);
}
export class C4 {
  m(a: string): void;
  m(a: number): void;
  m(a: unknown) {}
}

// Interfaces and type literals.
interface I1<T> {
  (a: string): void;
  (a: number): void;
  new (a: string): I1<T>;
  new (a: number): I1<T>;
  m(a: string): void;
  m(a: number): void;
  m2(a: T): void;
  m2(a: string): void;
  get g(): string;
  set g(v: string);
  m3?(a: string): void;
  m3?(a: number): void;
  m4(a: { [K in keyof T]: T[K] }): void;
  m4(a: { [K in keyof T]: string }): void;
  [Symbol.iterator](a: string): void;
  [Symbol.iterator](a: number): void;
}
export interface I2 {
  m(a: string): void;
  m(a: number): void;
}
declare interface I3 {
  (): void;
  (a: string): void;
}
type T1 = {
  (a: string): void;
  (a: number): void;
  m(a: string, b?: number): void;
  m(a: string): void;
};
type T2 = { m(a: string): void } & { m(a: number): void };
let v1: { (a: string): void; (a: number): void };
interface I4 {
  m(a: { n(a: string): void; n(a: number): void }): void;
  m(): void;
}

// Parameters.
declare function p1(a: string, b: number): void;
declare function p1(a: string, b: string): void;
declare function p2(a: string): void;
declare function p2(b: string, c?: number): void;
declare function p3(...a: string[]): void;
declare function p3(...a: number[]): void;
declare function p4(a?: string): void;
declare function p4(a?: number): void;
declare function p5(a: string): void;
declare function p5(a?: number): void;
declare function p6({ a }: { a: string }): void;
declare function p6({ a }: { a: number }): void;
declare function p7([a]: [string]): void;
declare function p7([a]: [number]): void;
declare function p9(a: string, b: string): void;
declare function p9(a: string, b: string, c: string, d: string): void;
declare function p10(a: string): void;
declare function p10(a: string, b: string, c?: string, ...d: string[]): void;
declare function p12(a: (string)): void;
declare function p12(a: string): void;
declare function p13(a: string): string;
declare function p13(a: number): number;
declare function p14(a: string): asserts a;
declare function p14(a: number): asserts a;
declare function p15(a: string): a is string;
declare function p15(a: number): a is string;
declare function p16(a: string /* one */): void;
declare function p16(a: string /* two */): void;
declare function p17(a: string | number): void;
declare function p17(a: boolean): void;
declare function p18(a: string, b: string): void;
declare function p18(a: number, b: number): void;
declare function p19(a: string): void;
declare function p19(): void;
declare function p20(): void;
declare function p20(...a: string[]): void;
declare function p21(this: Foo): void;
declare function p21(this: Foo, a: string): void;
declare function p22(this: Foo): void;
declare function p22(a: string): void;
declare function p23(this: void): void;
declare function p23(this: void, a: string): void;
declare function p24(a: string, ...b: string[]): void;
declare function p24(a: string, ...b: string[]): void;
declare function p25(...a: string[]): void;
declare function p25(...a: string[]): void;
declare function p26(a: string): void;
declare function p26(a: string, b?: string): void;
declare function p26(a: number): void;
export {};
