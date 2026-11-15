interface A { a: 1 }
interface B { b: 1 }
interface C { c: 1 }
declare const value: string;
type T20 = Z & unique symbol & (B & C) & (B | C) & [1, 2] & import('fs') & { [K in keyof A]: 1 } & { a: 1 } & typeof value & keyof A & this & number & string & (new () => A) & (() => void) & (A extends B ? 1 : 2) & void & undefined & null & A[] & A & B[number] & 'lit' & `t${string}`;
type T21 = `t${string}` & 'lit' & B[number] & A & A[] & null & undefined & void & (A extends B ? 1 : 2) & (() => void) & (new () => A) & string & number & this & keyof A & typeof value & { a: 1 } & { [K in keyof A]: 1 } & import('fs') & [1, 2] & (B | C) & (B & C) & unique symbol & Z;
