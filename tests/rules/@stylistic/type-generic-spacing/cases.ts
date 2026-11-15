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
