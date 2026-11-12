import type { TypedKey, TypedList, TypedSecond } from './keys';
// An alias that only names a conditional alias of another file, with a default type argument.
export type Key<Point, Value = any> = TypedKey<Point, Value>;
export interface Item {
  value: number;
}
export type List<Point, Value = any> = TypedList<Point, Value>;
export type Second<Point, Value = any> = TypedSecond<Point, Value>;
// Through two aliases.
export type KeyAgain<Point, Value = any> = Key<Point, Value>;
export type ListAgain<Point, Value = any> = List<Point, Value>;
