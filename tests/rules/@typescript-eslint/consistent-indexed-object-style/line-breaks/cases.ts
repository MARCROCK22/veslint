// consistent-indexed-object-style with CRLF line breaks.
interface A {
  [key: string]: Map<
    string,
    number
  >;
}
type B = {
  readonly [key: string]: number;
};
type C = {
  [K in 'a' | 'b']?: number;
};
interface D {
  // a comment
  [key: string]: number;
}
export type { A, B, C, D };
