// Spacing inside type arguments and type parameters, before type parameters, around defaults.
declare function call<T>(): T;
declare function tag<T>(strings: TemplateStringsArray): T;
const a1: Set< string> = new Set();
const a2: Map<string, number > = new Map< string, number >();
const a3 = call< string  >();
const a4 = tag< number >``;
const a5: Array</* comment */ number> = [];
const a6: Array<
	number> = [];
const a7: Array< 
	number> = [];
const a8: Array<number /* comment */> = [];
const a9: Array<(string)> = [];
const a10: Array< (string) > = [];
const a11: Array<number
> = [];
const a12: Array<number	> = [];
type T1< T> = T;
type T2<T > = T;
type T3 <T> = T;
type T4  < T , K > = [T, K];
type T5<T=true> = T;
type T6<T =true> = T;
type T7<T=  true> = T;
type T8<T  =  true> = T;
type T9<T = true> = T;
type T10<T extends boolean=true> = T;
type T11<T extends (boolean)=(true)> = T;
type T12<T = /* comment */ true> = T;
type T13<T /* = */ = true> = T;
type T14<T
	= true> = T;
type T15<T =
	true> = T;
type T16<T=(true)> = T;
type T17<
	T = true,
	K=false,
> = [T, K];
function f1 <T>(x: T): T { return x; }
function f2< T >(x: T): T { return x; }
function f3 /* comment */ <T>(x: T): T { return x; }
function f4/* comment */<T>(x: T): T { return x; }
const f5 = function <T>(x: T): T { return x; };
const f6 = function< T >(x: T): T { return x; };
const f7 = <T,>(x: T): T => x;
const f8 = < T >(x: T): T => x;
class C1 <T> {
	m1 <K>(x: K): K { return x; }
	m2< K >(x: K): K { return x; }
}
class C2<T> extends C1< T > {}
const C3 = class <T> {};
const C4 = class< T > {};
interface I1 <T> {
	m1 <K>(x: K): K;
	<K>(x: K): K;
	< K >(x: K): K;
	new <K>(x: K): K;
	new< K >(x: K): K;
	p1: <T>(x: T) => T;
	p2: < T >(x: T) => T;
	p3: new < T >(x: T) => T;
}
type T18 = I1< string >;
type T19 = typeof call< string >;
const a13 = new Map
	<string, number>();
type T20 <T> = T;
const a14: Array<　number> = [];
type T21<T = true> = T;
type T22<T = true> = T;
// 6.0: the space after type arguments and type parameters (`after`), and named function and class
// expressions.
const a15 = call<string> ();
const a16 = new Map<string, number> ();
const a17 = tag<number> `x`;
const a18 = call<string>/* comment */();
const a19 = call<string> /* comment */();
const a20 = new Map<string, number>;
const a21 = call<string>
	();
interface I2 {
	<K> (x: K): K;
	new<K> (x: K): K;
	new <K>(x: K): K;
	m <K> (x: K): K;
	m2<K>(x: K): K;
}
type T23 = <K> (x: K) => K;
type T24 = new<K> (x: K) => K;
type T25 = new <K>(x: K) => K;
const f9 = function named <T>(x: T): T { return x; };
const f10 = function named<T> (x: T): T { return x; };
const C5 = class Named <T> {};
const C6 = class Named<T> {};
const f11 = async <T>(x: T): Promise<T> => x;
function f12
<T>(x: T): T { return x; }
type T26 /* comment */<T> = T;
export type { T23, T24, T25, I2 };
export { a15, a16, a17, a18, a19, a20, a21, f9, f10, f11, f12, C5, C6 };
