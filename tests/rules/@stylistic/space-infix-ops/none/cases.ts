declare let a: number, b: number, s: string, o: { x?: number }, f: (n: number) => number;

export const r1 = a+b;
export const r2 = a +b;
export const r3 = a+ b;
export const r4 = a + b;
export const r5 = (a)+(b);
export const r6 = a/* c */+/* d */b;
export const r7 = a ** b, r8 = a**b, r9 = a<<b, r10 = a>>>b, r11 = a%b;
export const r12 = a|0;
export const r13 = a&&b, r14 = a||b, r15 = o.x??a;
export const r16 = 'x'in o, r17 = o instanceof(Object);
export const r18 = a===b, r19 = a!==b, r20 = a<=b, r21 = a>b;
a=b;
a+=b;
a **=b;
a>>>=b;
a ||=b;
o.x??=1;
s+=`t${a+b}`;
export const t1 = a?b:a;
export const t2 = a ? b:a;
export const t3 = a? b : a;
export const t4 = (a)?(b):(a);
export const t5 = a
  ? b
  : a;
let v1=1;
let v2: number=2;
let v3 /* c */=3;
const { x: v4=1, ...v5 }=o;
const [v6=1]=[a];
export { v1, v2, v3, v4, v5, v6 };
export function p1(x=1, y: number=2, { z }: { z: number }={ z: 1 }, [w]: number[]=[]): number {
  return x + y + z + w;
}
export const arrow = (x=1) => x;

export class K {
  a=1;
  b: number=2;
  c?=3;
  d?: number=4;
  ['e']=5;
  ['f']?=6;
  static g=7;
  #h=8;
  accessor i=9;
  j = 10;
  readonly k: string='';
}

export enum E { A=1, B = 2, C= 3, 'D' =4 }

type T1=string;
type T2<X>=X[];
type T3 = string|number;
type T4 = string |number;
type T5 = string& { a: 1 };
type T6 = |string|number;
type T7 =
  | string
  |number;
type T8 = string|(() => void);
type T10 = string|(number);
type T11 = A extends string?1:2;
type T12 = A extends string ? 1:2;
type A = string;
type T13 = (string|number)[];
type T14 = { a: string|number };
export function g(x: string|number = 1): string|number { return x; }
export type { T1, T2, T3, T4, T5, T6, T7, T8, T10, T11, T12, T13, T14 };

export const big = a+b*a-b/a;
export const neg = a+-b, neg2 = a- -b, inc = a+ +b;
export const cmp = f(a)+f(b);
