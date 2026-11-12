// prefer-readonly-parameter-types: a property of an instance of a generic mapped type without a
// readonly token is readonly when it is in the type it maps over, read from the declaration of
// the mapped type and the type arguments of the alias.
interface ReadonlyPoint {
  readonly x: number;
}
interface Point {
  x: number;
}
type Mapped<T> = { [K in keyof T]: T[K] };
type Chosen<T, K extends keyof T> = { [P in K]: T[P] };
type Without<T, K extends keyof T> = Chosen<T, Exclude<keyof T, K>>;
namespace Outer {
  export namespace x {
    export const value = 1;
  }
}
function overIntersections(
  a: Mapped<ReadonlyPoint & Point>,
  b: Mapped<Point & { x: number }>,
  c: Partial<ReadonlyPoint & Point>,
  d: Required<ReadonlyPoint & Point>,
  e: Pick<ReadonlyPoint & Point, 'x'>,
  f: Omit<ReadonlyPoint & Point & { y: number }, 'y'>,
  g: Chosen<ReadonlyPoint & Point, 'x'>,
  h: Without<ReadonlyPoint & Point & { y: number }, 'y'>,
  i: Mapped<Mapped<ReadonlyPoint & Point>>,
  j: Mapped<ReadonlyPoint>,
  k: Mapped<Point>,
) {}
function others(
  a: Mapped<typeof Outer>,
  b: Chosen<readonly [number, ...number[]], 'length'>,
  c: Chosen<readonly [number, ...number[]], 0>,
  d: Record<'x', number>,
  e: Readonly<Record<'x', number>>,
  f: Mapped<{ -readonly [K in keyof ReadonlyPoint]: ReadonlyPoint[K] } & Point>,
  g: Mapped<{ -readonly [K in keyof ReadonlyPoint]: ReadonlyPoint[K] } & ReadonlyPoint>,
) {}

// An instance without an alias, whose type arguments are those of the class, interface or alias
// that declares the member it is the type of.
interface ReadonlyAgain {
  readonly x: number;
}
interface Wrapper<T> {
  readonly inner: { [K in keyof T]: T[K] };
}
interface WrapperChosen<T, K extends keyof T> {
  readonly inner: { [P in K]: T[P] };
}
class WrapperClass<T> {
  readonly inner!: { [K in keyof T]?: T[K] };
}
type WrapperLiteral<T> = { readonly inner: { [K in keyof T]: T[K] } };
interface WrapperTwice<T> {
  readonly outer: Wrapper<T>;
}
function withoutAlias(
  a: Wrapper<ReadonlyPoint & Point>,
  b: Wrapper<ReadonlyPoint>,
  c: Wrapper<Point>,
  d: WrapperChosen<ReadonlyPoint & Point, 'x'>,
  e: WrapperClass<ReadonlyPoint & Point>,
  f: WrapperLiteral<ReadonlyPoint & Point>,
  g: WrapperLiteral<Point>,
  h: Wrapper<ReadonlyPoint | Point>,
  i: Wrapper<ReadonlyPoint | ReadonlyAgain>,
  j: WrapperTwice<ReadonlyPoint & Point>,
  k: WrapperTwice<Point>,
  l: Wrapper<typeof Outer>,
) {}
export { overIntersections, others, withoutAlias };
