// prefer-readonly-parameter-types: a conditional type asked through an alias imported from
// another file, which only names the conditional alias of a third file: the declaration is the
// body of that one, whose branches have types that are not followed (an indexed access, what an
// `infer` gives).
import type { Item, Key, KeyAgain, List, ListAgain, Second } from './imported';
import type { TypedKey, TypedList } from './keys';

export function byKey<Point, Value>(obj: Point | null | undefined, key: Key<Point, Value> | undefined, fallback: Value): Value;
export function byKey<Point, Value>(obj: Point | null | undefined, key: Key<Point, Value> | undefined, fallback?: Value): Value | undefined;
export function byKey<Point, Value>(obj: Point | null | undefined, key: Key<Point, Value> | undefined, fallback?: Value): Value | undefined {
  return obj == null || key == null ? fallback : undefined;
}
export type Formatter<T extends Item> = (entry: T, key: Key<T, number[] | number>, direction: 'x' | 'y') => number;
function uses<Point, Value>(
  a: Key<Point, Value>,
  b: Key<Point>,
  c: TypedKey<Point, Value>,
  d: TypedKey<Point>,
  e: Key<Point, Value[]>,
  f: Key<Item, number>,
  g: Key<Point & Item, Value>,
) {}
// The same aliases with a mutable branch, and an alias of this file that only names one.
type KeyHere<Point, Value = any> = TypedKey<Point, Value>;
type ListHere<Point, Value = any> = TypedList<Point, Value>;
function mutable<Point, Value>(
  a: List<Point, Value>,
  b: List<Point>,
  c: List<Point, Value> | undefined,
  d: Second<Point, Value>,
  e: KeyAgain<Point, Value>,
  f: ListAgain<Point, Value>,
  g: KeyHere<Point, Value>,
  h: ListHere<Point, Value>,
  i: TypedList<Point, Value>,
  j: Second<Item, Value>,
) {}
export type ListFormatter<T extends Item> = (entry: T, key: List<T, number>) => number;
export { uses, mutable };
