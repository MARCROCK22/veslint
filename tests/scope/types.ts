// TypeVisitor.
declare const value: { a: number; b: { c: string } };
declare const sym: unique symbol;
declare namespace NS { export type Inner<T> = T; export const v: number; export namespace Deep { export type D = string } }
type Alias = number;
type Generic<T, U extends T = T> = [T, U];
type Fn = (a: Alias, b?: string, ...rest: Alias[]) => void;
type GenFn = <T>(a: T, { b }: { b: T }, [c]: T[]) => T;
type Ctor = new (a: Alias) => object;
type AbsCtor = abstract new <T>(a: T) => T;
type Cond<T> = T extends string ? Alias : T extends (infer U)[] ? U : never;
type CondFn<T> = T extends (a: infer A, b: infer B) => infer R ? [A, B, R] : never;
type CondNested<T> = T extends { a: infer X extends string } ? { [K in X]: K } : X;
type InferMapped<T> = T extends { [K in infer Q extends string]: unknown } ? Q : never;
type Mapped<T> = { readonly [K in keyof T]?: T[K] };
type MappedAs<T> = { [K in keyof T as `get${string & K}`]: () => T[K] };
type Query = typeof value;
type QueryDeep = typeof value.b.c;
type QueryNs = typeof NS.v;
type QueryGeneric = typeof identity<string>;
type QueryImport = typeof import('m');
type Imported = import('m').Type<Alias>;
type ImportedDeep = import('m').a.b.C;
type Qualified = NS.Inner<Alias> | NS.Deep.D;
type Tuple = [a: Alias, b?: string, ...rest: Alias[]];
type Tpl = `a${Alias}b${keyof typeof value}`;
type Indexed = (typeof value)['a'];
type KeyOf = keyof typeof value;
type Literal = 'a' | 1 | true | null | undefined | -1 | 1n | `x`;
type Obj = {
  prop: Alias;
  readonly [sym]: Alias;
  ['computed']: Alias;
  [value.a]: Alias;
  method<T>(a: T): Alias;
  (call: Alias): Alias;
  new (construct: Alias): Obj;
  [index: string]: unknown;
  get acc(): Alias;
  set acc(v: Alias);
  optional?(o: Alias): void;
};
interface Iface<T, U = T> extends Base1, NS.Inner<Base2<T>> {
  prop: T;
  method(this: Iface<T>, a: U): this;
  <V>(call: V): U;
  new <W>(construct: W): Iface<W>;
  readonly [key: string]: unknown;
  [value.b.c](): void;
}
interface Base1 { x: Alias }
interface Base2<T> { y: T }
interface Merged { a: Alias }
interface Merged { b: Alias }
function identity<T>(x: T): T { return x; }
function isString(x: unknown): x is string { return typeof x === 'string'; }
function assertIt(x: unknown, y: Alias): asserts x is Alias { y; }
function assertOnly(x: unknown): asserts x {}
class Pred { is(): this is Pred { return true; } check(): asserts this is Pred {} }
function withThis(this: Pred, a: typeof this) { return a; }
let annotated: Generic<Alias, Alias>, fnVar: (p: Alias) => p is Alias;
let obj2: { [K in 'a' | 'b']: Alias } = { a: 1, b: 2 };
const casted = <Alias>(value.a as unknown), sat = value satisfies object, nn = value!.a, cc = [] as const, cc2 = <const>[];
function over(a: string): void;
function over(a: number): void;
function over(a: any) { a; }
declare function declared<T extends Alias>(p: T): T;
type Rec = { self: Rec; other: Array<Rec> };
type Unique = unique symbol;
type Intrinsic<S extends string> = Uppercase<S>;
type Opt = [Alias?, ...string[]];
type Paren = (Alias | string)[];
type Accessors = { get x(): Alias; set x(v: Alias) };
type ThisT = { m(): ThisT; n(this: ThisT): void };
type Big = bigint | symbol | object | never | unknown | any | void;
type Variance<in I, out O, in out IO> = [I, O, IO];
type ConstParam = <const C>(c: C) => C;
export { annotated, fnVar, obj2, casted, sat, nn, cc, cc2, over, declared, withThis, assertIt, assertOnly, isString };
export type { Fn, GenFn, Ctor, AbsCtor, Cond, CondFn, CondNested, InferMapped, Mapped, MappedAs, Query, QueryDeep, QueryNs, QueryGeneric, QueryImport, Imported, ImportedDeep, Qualified, Tuple, Tpl, Indexed, KeyOf, Literal, Obj, Iface, Merged, Rec, Unique, Intrinsic, Opt, Paren, Accessors, ThisT, Big, Variance, ConstParam };
