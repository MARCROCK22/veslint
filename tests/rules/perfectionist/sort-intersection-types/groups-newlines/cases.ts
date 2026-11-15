interface A { a: 1 }
interface B { b: 1 }
interface C { c: 1 }
declare const value: string;
type T22 =
  null
  & A
  & string;
type T23 =
  string
  & A
  & null;
type T24 =
  string
  & 
  A
  & 
  null;
