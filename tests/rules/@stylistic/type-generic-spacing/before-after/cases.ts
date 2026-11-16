declare function call<T>(): T;
declare function tag<T>(strings: TemplateStringsArray): T;
// `before: true` and `after: true`.
const a1 = call<string>();
const a2 = call <string> ();
const a3 = new Map<string, number>();
const a4 = new Map <string, number> ();
const a5 = tag<number>`x`;
const a6 = tag <number> `x`;
const a7: Array<number> = [];
const a8: Array <number> = [];
const a9 = call/* comment */<string>/* comment */();
type T1<T> = T;
type T2 <T> = T;
type T3< T > = T;
function f1<T>(x: T): T { return x; }
function f2 <T>(x: T): T { return x; }
const f3 = function<T>(x: T): T { return x; };
const f4 = function named<T>(x: T): T { return x; };
const f5 = <T,>(x: T): T => x;
class C1<T> {
	m1<K>(x: K): K { return x; }
	m2 <K>(x: K): K { return x; }
}
const C2 = class<T> {};
const C3 = class Named<T> {};
interface I1<T> {
	m1<K>(x: K): K;
	m2 <K> (x: K): K;
	<K>(x: K): K;
	new<K>(x: K): K;
	p1: <K>(x: K) => K;
	p2: new<K>(x: K) => K;
	p3: <K> (x: K) => K;
	p4: T;
}
type T4 = I1<string>;
type T5 = typeof call<string>;
export type { T1, T2, T3, T4, T5 };
export { a1, a2, a3, a4, a5, a6, a7, a8, a9, f1, f2, f3, f4, f5, C1, C2, C3 };
