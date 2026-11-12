// Type syntax tree-sitter reads differently from TypeScript: the duplicates must still be found.
type A = { a: 1 };
type Ctor = new () => A | A;
type Imported = import('./mod').Box<number> | import('./mod').Box<number>;
type Query = typeof import('./mod') | typeof import('./mod');
type Mapped<T> = { [K in keyof readonly T[]]: string | string };
interface Callable {
  a: number
  <T>(x: T): T | T
}
declare module './mod' {
  global {
    interface Augmented {
      x: string | string;
    }
  }
}
export type { Ctor, Imported, Query, Mapped, Callable };
// `readonly` binds tighter than a union.
type Ro = readonly string[] | readonly string[];
type Ro2 = readonly string[] | string | string;
type Ro3 = readonly string[] & readonly string[];
export type { Ro, Ro2, Ro3 };
// A type query of an import type in parentheses with a qualifier, an import type with type
// arguments in an array, and a union and an intersection that start with `|` and `&`.
type Paren = (typeof import('./mod').value)[] | (typeof import('./mod').value)[];
type Arrays = import('./mod').Box<number>[] | import('./mod').Box<number>[];
type Leading =
  | A
  | Ctor
  | A;
type LeadingAnd = & A & Ctor & A;
declare const leading: unknown;
const asserted = leading as
  | A
  | A;
export type { Paren, Arrays, Leading, LeadingAnd };
export { asserted };
