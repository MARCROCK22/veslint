interface A {
  a: string;
  b: number;
}
interface B {
  a: string,
  b: number,
}
interface C {
  a: string
  b: number
}
interface D { a: string; b: number }
interface E { a: string, b: number, }
interface F { a: string; b: number; }
type G = {
  a: string;
  b(): void,
  c: number
};
type H = { a: string, b: number };
type I = { a: string; };
interface J {
  a: string // comment
  b: number /* comment */
  c: boolean /* multi
  line */
  d: string
  // own line
  e: string;
}
interface K {
  a: string; /* comment */ b: number
}
interface L {
  [key: string]: unknown
  new (x: number): L
  (y: string): void
  method?(): void
}
interface M { a: string;
  b: number }
type N = { a: { x: string, y: number }; b: number };
type O = {
  a: '😀'
  b: 'ü',
};
export type { A, B, C, D, E, F, G, H, I, J, K, L, M, N, O };
