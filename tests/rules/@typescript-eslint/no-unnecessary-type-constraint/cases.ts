// no-unnecessary-type-constraint: `extends any` and `extends unknown` in a type parameter list (a
// parenthesized constraint too, which ESTree does not have), not in a mapped type or an `infer`;
// the suggestion removes ` extends X` (in a .ts file an arrow function needs no comma).
function f<T extends any>(t: T): T {
  return t;
}
function g<T extends unknown, U extends (unknown)>(t: T, u: U): [T, U] {
  return [t, u];
}
const h = <T extends any>(t: T): T => t;
const i = <T extends unknown = string>(t: T): T => t;
class C<T extends any> {
  m<U extends unknown>(u: U): U {
    return u;
  }
}
interface I<T extends unknown> {
  value: T;
}
type A<T extends any> = T[];
type Signature = <T extends unknown>(t: T) => T;
declare function d<const T extends unknown>(t: T): T;

// Not unnecessary, or not a type parameter list.
function j<T extends object>(t: T): T {
  return t;
}
type Mapped<T> = { [K in keyof T as K extends any ? K : never]: T[K] };
type Inferred<T> = T extends (infer U extends unknown)[] ? U : never;
type Unions<T extends unknown | string> = T;

export { f, g, h, i, C, d, j };
export type { I, A, Signature, Mapped, Inferred, Unions };
