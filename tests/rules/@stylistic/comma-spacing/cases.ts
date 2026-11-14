declare function foo(...args: unknown[]): void;
declare const a: number;
declare const b: number;
declare const c: number;

foo(a,b);
foo(a , b);
foo(a ,b);
foo(a, b,);
foo(a, b ,);
foo(a,/* c */b);
foo(a/* c */,b);
foo(a /* c */ , b);
foo(a,
  b);
foo(a
  ,b);
foo(a, // trailing
  b);
const arr1 = [a,b , c];
const arr2 = [a, , b];
const arr3 = [a,,b];
const arr4 = [ , a];
const arr5 = [,, a];
const arr6 = [(a), , b];
const arr7 = [a , , b];
const [x1, , y1] = [1, 2, 3];
const [x2,,y2] = [1, 2, 3];
const obj1 = {a,b};
const obj2 = {a: 1 ,b: 2,};
const { a: p1,b: p2 } = { a: 1, b: 2 };
function f1(x: number,y: number): number { return x + y; }
function f2<T,U>(x: T, y: U): [T,U] { return [x, y]; }
function f3<T,>(x: T): T { return x; }
const f4 = <T ,>(x: T): T => x;
type T1<A,B,> = Map<A,B>;
type T2 = [number,string , boolean];
type T3 = { a: number, b: string ,c: boolean };
interface I1<A , B> { a: A, b: B }
enum E1 { A,B , C }
let v1 = 1,v2 = 2 , v3 = 3;
for (let i = 0,j = 0; i < 1; i++,j++) { void i; void j; }
const s1 = (a,b);
const t1 = `${a},${b}`;
const t2 = `${a ,b}`;
import { readFileSync,writeFileSync } from 'node:fs';
export { f1,f2 , f3 };
void arr1; void arr2; void arr3; void arr4; void arr5; void arr6; void arr7;
void x1; void y1; void x2; void y2; void obj1; void obj2; void p1; void p2;
void f4; void E1; void v1; void v2; void v3; void s1; void t1; void t2;
void readFileSync; void writeFileSync;
export type { T1, T2, T3, I1 };
export const arr8 = [(a) ,, b];
export const arr9 = [a ,, b];
