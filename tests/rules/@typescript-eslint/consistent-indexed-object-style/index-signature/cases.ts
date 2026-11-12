// consistent-indexed-object-style with 'index-signature': `Record<K, V>` becomes
// `{ [key: K]: V }`, a fix when K is `string`, `number` or `symbol` and no comment would be lost.
type X = { value: string };
namespace A {
  export type Record<K, V> = Map<K, V>;
}

type R1 = Record<string, X>;
type R2 = Record<number, X>;
type R3 = Record<symbol, X>;
type R4 = Record<string | number, X>;
type R5 = Record<'a' | 'b', X>;
type R6<K extends string> = Record<K, X>;
type R7 = Record<(string), (X)>;
type R8 = Record</* comment */ string, X>;
type R9 = Record<string, /* comment */ X>;
type R10 = Record<string, Map</* inside */ string, X>>;
type R11 = Map<string, Record<number, X>>;
type R12 = Record<Exclude<'a' | 'b' | 'c', 'a'>, any>;
let r13: Record<string, X> = {};
function r14(arg: Record<string, X>): Record<number, X> {
  return arg;
}
type R15 = Record<string, Record<string, X>>;
type R16 = Record< string , X >;

// Not reported: other names, other numbers of type arguments, heritage clauses, and the other
// forms of indexed objects.
type S1 = Record;
type S2 = Record<string>;
type S3 = Record<string, number, unknown>;
type S4 = A.Record<string, X>;
interface S5 extends Record<string, X> {}
class S6 implements Record<string, X> {}
type S7 = Misc<string, unknown>;
type S8 = { [key: string]: X };
interface S9 {
  [key: string]: X;
}
type S10 = { [K in 'a']: X };
declare type Misc<A, B> = Map<A, B>;

export type { R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R15, R16, S1, S2, S3, S4, S5, S7, S8, S9, S10 };
export { r13, r14, S6 };
