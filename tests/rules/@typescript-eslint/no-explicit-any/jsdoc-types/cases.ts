// JSDoc types, which TypeScript's parser reads in a TypeScript file (its checker reports them):
// `T!`, `?T` and `*` are no `any` for typescript-estree; the `any` inside them is.
type T = string;
export type V = T!;
export type W = ?T;
export type X = *;
export type Y = Array<T![]>;
export type Z = ?(any | T)!;
export function f(...a: any[]): V {
  return a[0];
}
