interface A { a: 1 }
interface B { b: 1 }
interface C { c: 1 }
declare const value: string;
type T33 = { b: () => void } & (() => void) & A;
