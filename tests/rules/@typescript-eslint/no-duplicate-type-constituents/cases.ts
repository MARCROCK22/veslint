interface Box {
  value: number;
}
interface Other {
  other: string;
}
enum Color {
  Red,
  Green,
}
type Alias = string;
type Undef = undefined;
declare const sample: string;

// Unions: the same node, or the same type.
type A = string | string;
type B = string | number | string;
type C = (string | number) | string;
type D = string | (string | number);
type E = 'a' | "a";
type F = Array<string> | string[];
type G = { a: string } | { a: string };
type H = { a: string; } | { a: string, };
type I = (() => void) | (() => void);
type J = Alias | string;
type K = | string | string;
type L = 1 | 1.0;
type M = Color.Red | Color.Red;
type N = typeof sample | typeof sample;
type O<T> = T | T;
type P = Array<string | string>;
type Q = {
  a: string;
} | {
  a: string;
};
type R = (string) | string;
// Types TypeScript cannot resolve are only compared as nodes.
type S = Missing | Missing;
type T = Missing | Unknown;
// Not duplicated.
type U = string | number;
type V = Color | Color.Red;
type W = true | boolean;

// Intersections.
type X = Box & Box;
type Y = Box & Other & Box;
type Z = (Box & Other) & Box;
type AA = (string | string) & Box;
type AB = (Box & Box) | string;
type AC = Box & (Other & Box);

// Explicit undefined on optional parameters.
function optional(a?: string | undefined): void {}
function first(a?: undefined | string): void {}
function wrapped(a?: (string | undefined)): void {}
function nested(a?: string | (number | undefined)): void {}
function aliased(a?: string | Undef): void {}
function twice(a?: string | undefined | undefined): void {}
const arrow = (a?: number | undefined) => a;
type Callback = (a?: string | undefined) => void;
type Constructor = new (a?: string | undefined) => object;
interface WithMethod {
  method(a?: string | undefined): void;
  (a?: string | undefined): void;
  new (a?: string | undefined): WithMethod;
}
declare function declared(a?: string | undefined): void;
class Holder {
  constructor(private kept?: string | undefined, readonly also?: number | undefined) {}
  method(a?: string | undefined): void {}
  overload(a?: string | undefined): void;
  overload(a?: string | undefined): void {}
}
abstract class Base {
  abstract run(a?: string | undefined): void;
}
const literal = {
  method(a?: string | undefined): void {},
};
// Not reported: not optional, not a parameter, or no undefined.
function required(a: string | undefined): void {}
interface Props {
  a?: string | undefined;
}
function nullable(a?: string | null): void {}

export type { A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z };
export type { AA, AB, AC, Callback, Constructor, WithMethod, Props };
export { optional, first, wrapped, nested, aliased, twice, arrow, declared, Holder, Base, literal, required, nullable };
