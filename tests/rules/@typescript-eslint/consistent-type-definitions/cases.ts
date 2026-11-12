// Reported with the default option ('interface'), and fixed.
type T1 = { a: string };
type T2 = {
  a: string;
  b: number;
};
type T3<U> = { a: U };
type T4<U extends object = {}> = { a: U }
type T5 = ({ a: string });
type T6 = (({ a: string }));
export type T7 = { a: string };
declare type T8 = { a: string };
export declare type T9 = { a: string };
type /* c1 */ T10 /* c2 */ = /* c3 */ { a: string } /* c4 */;
type T11 =
  // a line comment
  { a: string };
type T12 = {}
type T13 = { a: string } // no semicolon
namespace N1 {
  type T14 = { a: number };
  export type T15 = { b: number };
}
declare global {
  type T16 = { a: string };
}
type T17 = { (): void };
type T18 = { new (): T18 };
type T19 = { [key: string]: number };
type T20 = { a: string }; type T21 = { b: string };
type T22<
  U,
> = {
  a: U;
};

// Not reported.
type T23 = { a: string } | { b: number };
type T24 = { a: string }[];
type T25 = string;
type T26 = { [K in 'a' | 'b']: K };
type T27<U> = { readonly [K in keyof U]?: U[K] };
interface I1 {
  a: string;
}
export {};
