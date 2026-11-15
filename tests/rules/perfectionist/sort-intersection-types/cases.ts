interface A { a: 1 }
interface B { b: 1 }
interface C { c: 1 }
declare const value: string;
// Reported and fixed.
type T1 = C & B & A;
type T2 = 'b' & 'a';
type T3 =
  C
  & B
  & A;
type T4 =
  & C
  & B
  & A;
type T5 =
  B /* after B */
  & A // after A;
type T6 =
  & // above B
  B
  & /* above A */ A;
type T7 = (C) & (A) & B;
type T8 = { b: 1 } & { a: 1 };
type T9 = number & boolean & any;
type T10 = A[] & A;
type T11 = Array<B> & Array<A>;
type T12 = (B & C) & A;
function f(x: B & A): void {}
let v: C & B & A;
type T13 = `b` & `a`;
type T14 = 2 & 1 & -1;
type T15 = B & A & B;
// Not reported.
type T16 = A & B & C;
type T17 = A;
type T18 =
  & A
  & B;
type T19 =
  C
  & // eslint-disable-next-line perfectionist/sort-intersection-types
  A
  & B;
// Callable types, ignored.
type T34 = B & (() => void) & A;
type T35 = B & { (): void } & A;
type T36 = B & { m(): void } & A;
type T37 = B & { p: () => void } & A;
type T38 = B & { p: { q: new () => A } } & A;
type T39 = B & { new (): A } & A;
type T40 = B & { [k: string]: () => void } & A;
