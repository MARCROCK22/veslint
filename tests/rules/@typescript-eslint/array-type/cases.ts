// array-type: `T[]` or `Array<T>` (and `readonly T[]`, `ReadonlyArray<T>` or `Readonly<T[]>`) as
// the options ask. The same file runs with every set of options of the subdirectories.
type Simple = string;
namespace Ns {
  export type Name = string;
}
class Self {
  items: this[] = [];
  generic: Array<this> = [];
}

// Arrays of simple types.
let a1: string[] = [];
let a2: Array<string> = [];
let a3: readonly number[] = [];
let a4: ReadonlyArray<number> = [];
let a5: Readonly<boolean[]> = [];
let a6: Simple[] = [];
let a7: Array<Ns.Name> = [];
let a8: null[] = [];
let a9: Array<undefined> = [];
let a10: bigint[] = [];
let a11: Array<object> = [];
let a12: never[] = [];
let a13: Array<unknown> = [];
let a14: symbol[] = [];
let a15: Array<void> = [];
let a16: any[][] = [];
let a17: Array<Array<number>> = [];
let a18: Array<number[]> = [];
let a19: Array<Array> = [];

// Arrays of other types.
let b1: (string | number)[] = [];
let b2: Array<string | number> = [];
let b3: readonly (string | number)[] = [];
let b4: ReadonlyArray<string | number> = [];
let b5: Readonly<(string | number)[]> = [];
let b6: Array<() => void> = [];
let b7: (() => void)[] = [];
let b8: Array<new () => void> = [];
let b9: Array<{ a: string } & { b: number }> = [];
let b10: Array<keyof Self> = [];
let b11: Array<readonly string[]> = [];
let b12: Array<unique symbol> = [];
let b13: Array<'literal'> = [];
let b14: Array<typeof a1> = [];
let b15: Array<[string, number]> = [];
let b16: Array<Map<string, number>> = [];
let b17: Array<Ns.Name[]> = [];
let b18: Array<Array<string> | number> = [];
let b19: Array<ReadonlyArray<string>> = [];
let b20: Array<ReadonlyArray<string>>[] = [];
let b21: ReadonlyArray<ReadonlyArray<number>> = [];
let b22: ReadonlyArray<readonly number[]> = [];
let b23: readonly (readonly number[])[] = [];
let b24: readonly number[][] = [];
type B25<T> = Array<T extends string ? string : number>;
type B26<T> = (T extends string ? string : number)[];
type B27<T> = T extends Array<infer U> ? U : never;
type B28<T> = T extends (infer U)[] ? U : never;
let b29: Array<`template`> = [];
let b30: Array<{ [key: string]: number }> = [];

// Parentheses, comments and spacing.
let c1: Array<(string)> = [];
let c2: (string)[] = [];
let c3: readonly (string[]) = [];
let c4: readonly(string)[] = [];
let c5: (ReadonlyArray<string>)[] = [];
let c6: ((ReadonlyArray<string>))[] = [];
let c7: Array< string > = [];
let c8: Array</* comment */ string> = [];
let c9: string /* comment */ [] = [];
let c10: Readonly<(string[])> = [];
let c11: Array<(string | number)> = [];
let c12: readonly    (readonly string[])[] = [];
let c13: (Array<string>) = [];
let c14: Readonly<string[]>[] = [];
let c15: (Readonly<string[]>)[] = [];
let c16: Readonly<string[][]> = [];

// In other places.
function f1(x: Array<string>): Array<string> {
  return x;
}
const f2 = <T,>(x: T[]): Array<T> => [x[0]];
let d1 = <Array<string>>[];
let d2 = [] as Array<number>;
let d3 = f1([] satisfies string[]);
declare function d4<E extends Readonly<string[]>>(extra: E): E;
interface D5 {
  a: Array<string>;
  b: readonly string[];
}
class D6 implements D5 {
  a: string[] = [];
  b: ReadonlyArray<string> = [];
}
let d7: Map<string, Array<number>> = new Map();
let d8: { [key: string]: number[] } = {};

// Not reported: the other names, `Array` without one type argument, heritage and expressions, or a
// type of that name declared in the file outside the global scope.
let e1: Array = [];
let e2: Readonly<string> = '';
let e3: Readonly = [];
let e4: Ns.Name[] | Array<string, number> = [];
class E5 extends Array<string> {}
interface E6 extends Array<string> {}
let e7 = new Array<string>();
let e8: typeof Array<string>;
let e9: Ns.Array<string> = [];
type E10<Array extends unknown[]> = { array: Array };
type E11<ReadonlyArray> = { array: ReadonlyArray };
namespace E12 {
  type Array<T> = T;
  type ReadonlyArray<T> = T;
  export const x: Array<string> = '';
  export const y: ReadonlyArray<string> = '';
}
function e13<Readonly>(x: Readonly<string[]>) {
  return x;
}
declare module 'array-module' {
  type Array<Y> = Y;
  const y: Array<2>;
}

// The nested cases of the upstream tests, which ESLint fixes in several passes.
let g1: ({ foo: Array<Array<Bar> | Array<any>> })[] = [];
class G2<T = Array<Array<Bar>>> extends Bar<T, Array<T>> implements Baz<Array<T>> {
  private s: Array<T>;
  constructor(p: Array<T>) {
    super();
    this.s = p;
  }
}
interface G3 {
  outerProperty: Array<
    ({ innerPropertyOne: string } & { innerPropertyTwo: string })
  >;
}
type G4 = {
  outerProperty: Array<
    { innerPropertyOne: string } & { innerPropertyTwo: string }
  >;
};
const g5: Array<(string|number)> = [];
let g6: Array<any[]>[] = [];
let g7: Array<Array[]>[] = [];
type G8 = readonly(readonly string[])[];
declare class Bar<A = unknown, B = unknown> {}
declare interface Baz<A> {}

export {
  g1, G2, g5, g6, g7,
  a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19,
  b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15, b16, b17, b18, b19, b20,
  b21, b22, b23, b24, b29, b30,
  c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16,
  f2, d1, d2, d3, d6 as D6Value, d7, d8, e1, e2, e3, e4, e5 as E5Value, e7, e8, e9, e13,
};
const d6 = D6;
const e5 = E5;
export type { B25, B26, B27, B28, D5, E6, E10, E11, G3, G4, G8 };
