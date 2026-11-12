enum Color {
  Red = 'red',
}
type Letters = 'a' | 'b';
type Bool = boolean;
type Err = Missing;
type Reversed = 'b' | 'a';
type AnyAlias = any;
type UnknownAlias = unknown;
type NeverAlias = never;
type Template = `a${string}`;
type BigOne = 1n;

// Unions: top and bottom types.
type A = any | string;
type B = unknown | string;
type C = never | string;
type D = Missing | string;
type E = Err | string;
type F = Array<any | number>;
// `never` in a return type is allowed.
declare function returns(): never | string;
type Fn = () => never | string;
interface WithMethod {
  method(): never | string;
}
declare function parameter(value: never | string): void;
const arrow = (): (never | string) => 'x';
class Holder {
  get value(): never | string {
    return 'x';
  }
}
declare function isText(value: unknown): value is never | string;

// Unions: literals overridden by their primitive.
type G = 'a' | string;
type H = 1 | number | 2n | bigint | true | boolean;
type I = 'a' | 'b' | string;
type J = Letters | string;
type K = `a${string}` | string;
type L = `abc` | string;
type M = -1 | number;
type N = Bool | false;
type O = 0x10 | 1.50 | number;
type P = 'a"b' | string;
type Q = (any | string) | number;
type R = ('a' | 1) | string | number;
type AG = Reversed | string;
type AH = AnyAlias | UnknownAlias | NeverAlias | string;
type AI = Template | BigOne | -1n | bigint | string;
type AJ = never | never;
// Not redundant.
type S = string | number;
type T = Color.Red | string;
type U = 'a' | 1;

// Intersections.
type V = string & 'a';
type W = any & string;
type X = never & string;
type Y = unknown & string;
type Z = Letters & string;
type AA = (1 | 'a') & number & string;
type AB = number & 1;
type AC = { a: 1 } & string;
type AD = boolean & true;
type AE = Missing & string;
type AF = (string | number) & string;
type AK = Reversed & string;
type AL = UnknownAlias & NeverAlias & AnyAlias;

export type { A, B, C, D, E, F, Fn, WithMethod, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U };
export type { V, W, X, Y, Z, AA, AB, AC, AD, AE, AF, AG, AH, AI, AJ, AK, AL };
export { returns, parameter, arrow, Holder, isText };
