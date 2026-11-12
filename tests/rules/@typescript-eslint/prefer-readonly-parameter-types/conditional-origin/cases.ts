// prefer-readonly-parameter-types: conditional types without an alias of their own, whose
// declaration is found from where the type comes from: the declaration of a member of a generic
// class or interface, the alias a type reference names, the type arguments of the use.
import type * as imported from './imported';
import type {
  ChainSameCheck,
  ChainTwoImported,
  DecidedFalse,
  DecidedNested,
  DecidedTrue,
  DecidedTrueAgain,
} from './imported';
interface Mutable {
  a: number;
}
interface Frozen {
  readonly a: number;
}

// The type of a member of a generic class or interface.
class Box<T, V> {
  readonly value!: T extends string ? V : never;
}
interface Holder<T, V> {
  readonly list: T extends string ? V[] : never;
  readonly one: T extends string ? V : never;
}
interface OnlyOne<T, V> {
  readonly one: T extends string ? V : never;
}
interface Optional<T, V> {
  readonly one?: T extends string ? V : never;
}
interface Derived<U> extends OnlyOne<U, Mutable> {
  readonly more: U extends string ? Frozen : never;
}
class DerivedBox<U> extends Box<U, Mutable> {}
interface Dictionary<T, V> {
  readonly [key: string]: T extends string ? V : never;
}
interface DictionaryMutable<T, V> {
  readonly [key: string]: T extends string ? V[] : never;
}
function members<U>(
  a: Box<U, Mutable>,
  b: Holder<U, Mutable>,
  c: Holder<U, Frozen>,
  d: OnlyOne<U, Mutable>,
  e: OnlyOne<U, Mutable[]>,
  f: Optional<U, Mutable>,
  g: Derived<U>,
  h: DerivedBox<U>,
  i: Dictionary<U, Mutable>,
  j: DictionaryMutable<U, Mutable>,
  k: Box<U, U extends string ? Mutable : never>,
  l: Box<U, U extends string ? Frozen : never>,
) {}

// The type of a property of an object type written in an alias, or in place.
type Literal<T, V> = { readonly a: T extends string ? V : never };
type LiteralMutable<T, V> = { readonly a: T extends string ? V[] : never };
type Outer<T, V> = { readonly inner: { readonly a: T extends string ? V : never } };
type OuterMutable<T, V> = { readonly inner: { readonly a: T extends string ? V : never; readonly b: T extends string ? V[] : never } };
type LiteralAlias<T, V> = Literal<T, V>;
function literals<U>(
  a: Literal<U, Mutable>,
  b: LiteralMutable<U, Mutable>,
  c: Outer<U, Mutable>,
  d: OuterMutable<U, Mutable>,
  e: LiteralAlias<U, Mutable>,
  f: { readonly a: U extends string ? Mutable : never },
  g: { readonly a: U extends string ? Frozen : never },
  h: Literal<U, Mutable> | undefined,
  i: Literal<U, Mutable> | LiteralMutable<U, Frozen>,
) {}

// The first condition is decided and TypeScript goes on with another conditional type, which has
// no alias.
type ChainTwo<T, W, V> = T extends string ? V[] : W extends number ? V : never;
type NestedTrue<T, W, V> = T extends string ? (W extends 'a' ? V : readonly V[]) : never;
type NestedTrueMutable<T, W, V> = T extends string ? (W extends 'a' ? V : V[]) : never;
type ChainTwoAlias<T, W, V> = ChainTwo<T, W, V>;
function decided<U>(
  a: ChainTwo<bigint, U, Mutable>,
  b: NestedTrue<'x', U, Mutable>,
  c: NestedTrueMutable<'x', U, Mutable>,
  d: ChainTwo<bigint, U, Mutable[]>,
  e: ChainTwoAlias<bigint, U, Mutable>,
  f: ChainTwoImported<bigint, U, Mutable>,
  g: ChainSameCheck<number | U, Mutable>,
  h: ChainTwo<U, number, Mutable>,
  i: ChainTwo<bigint, number, Mutable>,
) {}

// The members of the union a conditional type gives for a union.
function distributed<U, W>(
  a: ChainTwo<bigint, U | W, Mutable>,
  b: NestedTrue<'x', U | W, Mutable>,
  c: NestedTrueMutable<'x', U | W, Mutable>,
  d: ChainTwo<bigint, U | W, Mutable> | undefined,
) {}

// Elements of arrays and tuples, and members of the types above.
interface Wrapped<W> {
  readonly chain: ChainTwo<bigint, W, Mutable>;
  readonly list: readonly ChainTwo<bigint, W, Mutable>[];
}
interface WrappedMutable<W> {
  readonly chain: NestedTrueMutable<'x', W, Mutable>;
}
function elements<U>(
  a: readonly ChainTwo<bigint, U, Mutable>[],
  b: ReadonlyArray<ChainTwo<bigint, U, Mutable>>,
  c: readonly [ChainTwo<bigint, U, Mutable>, NestedTrue<'x', U, Mutable>],
  d: readonly [first: ChainTwo<bigint, U, Mutable>, second?: NestedTrueMutable<'x', U, Mutable>],
  e: Wrapped<U>,
  f: WrappedMutable<U>,
  g: readonly NestedTrueMutable<'x', U, Mutable>[],
) {}

// A decided condition whose branch names another alias: the type has the declaration of the
// other, and the alias of the use when that is imported or is the body of an alias.
type Other<T, V> = T extends string ? V : never;
type DecidedAlias<T, V> = string extends string ? Other<T, V> : V[];
type DecidedAliasFalse<T, V> = string extends number ? V[] : Other<T, V>;
type DecidedAliasAgain<T, V> = DecidedAlias<T, V>;
function decidedAlias<U>(
  a: DecidedAlias<U, Mutable>,
  b: DecidedAliasFalse<U, Mutable>,
  c: DecidedAliasAgain<U, Mutable>,
  d: DecidedTrue<U, Mutable>,
  e: DecidedFalse<U, Mutable>,
  f: DecidedNested<U, Mutable>,
  g: DecidedTrueAgain<U, Mutable>,
  h: DecidedTrue<U, Mutable[]>,
) {}

// The type argument of the use is the conditional type.
type Pick1<T, V> = T extends string ? V : never;
function passed<U>(
  a: Pick1<string, U extends string ? Mutable : never>,
  b: Pick1<string, U extends string ? Frozen : never>,
  c: Pick1<string, Pick1<U, Mutable>>,
  d: Pick1<string, ChainTwo<bigint, U, Mutable>>,
  e: Pick1<U, U extends string ? Mutable : never>,
) {}

// Through a mapped type: `{ [K in keyof T]: T[K] }` has the properties of T, and any other has
// the type its template declares.
type Template<T, V> = { readonly [K in keyof T]: T[K] extends string ? V : never };
type TemplateMutable<T, V> = { readonly [K in keyof T]: T[K] extends string ? V[] : never };
type Keyed<T, V> = { readonly [K in keyof T]: K extends 'a' ? V : never };
function mapped<U>(
  a: Readonly<OnlyOne<U, Mutable>>,
  b: Readonly<Holder<U, Mutable>>,
  c: Readonly<Partial<OnlyOne<U, Mutable>>>,
  d: Readonly<Required<Optional<U, Mutable>>>,
  e: Readonly<Pick<Holder<U, Mutable>, 'one'>>,
  f: Readonly<Pick<Holder<U, Mutable>, 'list'>>,
  g: Readonly<Omit<Holder<U, Mutable>, 'list'>>,
  h: Template<{ a: U }, Mutable>,
  i: TemplateMutable<{ a: U }, Mutable>,
  j: Keyed<{ a: U }, Mutable>,
  k: Readonly<Literal<U, Mutable>>,
  l: Readonly<Box<U, Mutable>>,
) {}

// Through an intersection and an indexed access.
function combined<U>(
  a: OnlyOne<U, Mutable> & { readonly extra: number },
  b: Holder<U, Frozen> & { readonly extra: number },
  c: Holder<U, Mutable>['one'],
  d: Holder<U, Mutable>['list'],
  e: Literal<U, Mutable>['a'],
  f: Outer<U, Mutable>['inner'],
  g: OuterMutable<U, Mutable>['inner'],
  h: Box<U, Mutable>['value'] | undefined,
) {}

// A parameter property, a default type argument, classes and interfaces that extend others, and
// declarations inside a generic function.
class WithProperty<T, V> {
  constructor(readonly value: T extends string ? V : never) {}
}
class WithMutableProperty<T, V> {
  constructor(readonly value: T extends string ? V[] : never) {}
}
type WithDefault<T, V = Mutable> = T extends string ? V : never;
type WithDefaultList<T, V = Mutable, L = V[]> = T extends string ? L : never;
interface Level2<A> extends Derived<A> {}
interface Level3 extends Level2<string> {}
interface Renamed<A, B> extends Holder<B, A> {}
class DerivedTwice<W> extends DerivedBox<W> {}
function heritage<U>(
  a: WithProperty<U, Mutable>,
  b: WithMutableProperty<U, Mutable>,
  c: WithDefault<U>,
  d: WithDefaultList<U>,
  e: Level2<U>,
  f: Level3,
  g: Renamed<Mutable, U>,
  h: DerivedTwice<U>,
  i: WithDefault<U, Mutable[]>,
) {}
function local<U>() {
  type Local<V> = U extends string ? V : never;
  interface LocalHolder<V> {
    readonly one: U extends string ? V : never;
  }
  class LocalBox<V> {
    readonly value!: U extends string ? V : never;
  }
  return (a: Local<Mutable>, b: LocalHolder<Mutable>, c: LocalBox<Mutable>, d: Local<Mutable>[]) => [a, b, c, d];
}

// What an `infer` gives, an alias that names itself and other types that are not followed: the
// branches of the type itself are looked at.
type Unwrap<T> = T extends readonly (infer E)[] ? E : T;
type Deep<T> = T extends readonly (infer E)[] ? Deep<E> : T;
type Again<T, V> = T extends string ? V : Again<T, V[]>;
type First<T, V> = T extends readonly [infer F, ...unknown[]] ? F | V : never;
declare const boxed: Box<string, Mutable>;
function notFollowed<U>(
  a: Unwrap<U>,
  b: Unwrap<readonly Mutable[]>,
  c: Unwrap<readonly (U extends string ? Mutable : never)[]>,
  d: Deep<U>,
  e: Deep<readonly Mutable[][]>,
  f: Again<U, Mutable>,
  g: First<U, Frozen>,
  h: First<readonly [U extends string ? Mutable : never], Frozen>,
  i: typeof boxed.value,
  j: readonly [...ChainTwo<bigint, U, Frozen>[]],
) {}

// Parameters whose type is asked at the parameter: a default value, and an optional one.
function defaults<U>(
  a: ChainTwo<bigint, U, Mutable> | undefined = undefined,
  b?: ChainTwo<bigint, U, Mutable>,
  c: Box<U, Mutable> | undefined = undefined,
  d: Holder<U, Mutable> | undefined = undefined,
) {}

// The same shape with other answers, a qualified name, and a union of a conditional type.
namespace Types {
  export type Chosen<T, V> = T extends string ? V : never;
  export type ChosenList<T, V> = T extends string ? V[] : never;
  export interface Kept<T, V> {
    readonly one: T extends string ? V : never;
  }
}
type Same<T, W, V> = T extends string ? V[] : W extends string ? V : never;
type Mixed<T, V> = T extends string ? V | Pick1<T, V[]> : never;
type MixedReadonly<T, V> = T extends string ? V | Pick1<T, readonly V[]> : never;
function shapes<U>(
  a: Types.Chosen<U, Mutable>,
  b: Types.ChosenList<U, Mutable>,
  c: Types.Kept<U, Mutable>,
  d: Same<U, U, Mutable>,
  e: Same<bigint, U, Mutable>,
  f: Mixed<U, Mutable>,
  g: MixedReadonly<U, Mutable>,
  h: Pick1<U | number, Mutable>,
  i: Pick1<any, Mutable>,
  j: Pick1<U, Mutable> extends infer R ? R : never,
) {}
// A type with an alias whose body is a conditional type: its declaration is that body or one
// down its false branches, whatever an `infer` or the other branches give.
type Element<T> = T extends readonly (infer E)[] ? E : T;
type ElementList<T> = T extends readonly (infer E)[] ? E[] : T;
type Thenable<T> = T extends null | undefined ? T : T extends { then(onfulfilled: infer F): unknown } ? (F extends (value: infer V) => unknown ? Thenable<V> : never) : T;
interface WithElement<T> {
  readonly element: T extends readonly (infer E)[] ? E : T;
}
function aliased<U>(
  a: Awaited<U & Mutable>,
  b: Awaited<U>,
  c: Element<U & Mutable>,
  d: ElementList<U & Mutable>,
  e: Thenable<U & Mutable>,
  f: NonNullable<U & Mutable>,
  g: Exclude<U & Mutable, string>,
  h: Extract<U, Mutable>,
  i: ReturnType<U & (() => Mutable)>,
  j: WithElement<U & Frozen>,
) {}
// An interface declared in two parts, a namespace import, arrays and tuples behind aliases and
// unions, a default type argument that is a conditional type, a check type that is not a type
// parameter, and a conditional type in a branch of another.
interface Merged<T, V> {
  readonly first: T extends string ? V : never;
}
interface Merged<T, V> {
  readonly second: T extends number ? V : never;
}
interface MergedMutable<T, V> {
  readonly first: T extends string ? V : never;
}
interface MergedMutable<T, V> {
  readonly second: T extends number ? V[] : never;
}
type List<T> = readonly T[];
type Pair<A, B> = readonly [first: A, second?: B];
type DefaultConditional<T, V = T extends string ? Mutable : never> = T extends number ? V : never;
type Tupled<T, V> = [T] extends [string] ? V : never;
type TupledMutable<T, V> = [T] extends [string] ? V[] : never;
type Either<T, V> = (T extends string ? V : never) | (T extends number ? readonly V[] : never);
type EitherMutable<T, V> = (T extends string ? V : never) | (T extends number ? V[] : never);
type Inside<T, V> = T extends string ? { readonly inner: T extends 'a' ? V : never } : never;
type InsideMutable<T, V> = T extends string ? { readonly inner: T extends 'a' ? V[] : never } : never;
interface OrNothing<T, V> {
  readonly value: (T extends string ? V : never) | undefined;
}
function more<U, W>(
  a: Merged<U, Mutable>,
  b: MergedMutable<U, Mutable>,
  c: imported.DecidedTrue<U, Mutable>,
  d: imported.ChainTwoImported<bigint, U, Mutable>,
  e: List<ChainTwo<bigint, U, Mutable>>,
  f: List<NestedTrueMutable<'x', U, Mutable>>,
  g: Pair<ChainTwo<bigint, U, Mutable>, NestedTrue<'x', U, Mutable>>,
  h: Pair<ChainTwo<bigint, U, Mutable>, NestedTrueMutable<'x', U, Mutable>>,
  i: readonly ChainTwo<bigint, U, Mutable>[] | readonly NestedTrue<'x', U, Mutable>[],
  j: DefaultConditional<U>,
  k: Tupled<U, Mutable>,
  l: TupledMutable<U, Mutable>,
  m: Either<U, Mutable>,
  n: EitherMutable<U, Mutable>,
  o: Inside<U, Mutable>,
  p: InsideMutable<U, Mutable>,
  q: OrNothing<U, Mutable>,
  r: Box<U | W, Mutable>,
  s: Holder<U | W, Frozen>,
) {}
export {
  aliased,
  more,
  members,
  literals,
  decided,
  distributed,
  elements,
  decidedAlias,
  passed,
  mapped,
  combined,
  heritage,
  local,
  notFollowed,
  defaults,
  shapes,
};
