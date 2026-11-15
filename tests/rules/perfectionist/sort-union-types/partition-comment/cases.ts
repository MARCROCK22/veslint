interface A { a: 1 }
interface B { b: 1 }
interface C { c: 1 }
declare const value: string;
type T26 =
  | C
  | B
  | // part
  E
  | D;
type T27 =
  C
  | // part
  B
  | A;
