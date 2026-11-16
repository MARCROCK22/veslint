// `ignoreOperators`: the operators that are not checked.
declare let a: number;
declare let b: number;
declare let s: string | undefined;
export const x1=a+b;
export const x2 = a*b;
export const x3 = a-b;
export const x4 = a&&b;
export const x5 = a||b;
export const x6 = a?b:a;
export const x7 = a ? b:a;
s??='x';
s ||='x';
a+=1;
a=2;
type U1 = string|number;
type U2 = string&{ a: 1 };
type C1 = U1 extends string?1:2;
type C2 = U1 extends string ? 1:2;
type D1<T=true> = T;
export function f(x=1, y: number=2): number { return x + y; }
export class K { p=1; q?: number=2; static r:number=3; }
enum E { A=1, B= 2 }
export type { U1, U2, C1, C2, D1 };
export { E };
