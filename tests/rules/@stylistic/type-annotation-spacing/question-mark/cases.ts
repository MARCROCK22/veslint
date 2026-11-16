// The colons of type annotations (no space before, one after by default), and `=>`, no longer checked in 6.0.
let a1:string;
let a2 : string;
let a3 :string;
let a4: string;
const a5 : number = 1;
function f1(x:number, y :string, z ?: boolean, w? :number):void {}
function f2(x: number): void {}
function f3() :void {}
function f4()  :  void {}
const f5 = function (x :number) :number { return x; };
const f6 = (x:number):number => x;
const f7 = async (x :number) : Promise<number> => x;
class C1 {
	p1:string = '';
	p2 :string = '';
	p3 ?:string;
	p4? : string;
	static p5 : number = 1;
	m1(x:number) :void {}
	m2() : string { return ''; }
	constructor(x :number);
	constructor(x: number) {}
	accessor p6 :number = 1;
	get g() :number { return 1; }
	set s(value :number) {}
}
abstract class C2 {
	abstract p1 :string;
	abstract m1() :void;
	[key :string] :unknown;
}
interface I1 {
	p1:string;
	p2 ?: number;
	m1(x :number) :void;
	m2? () :void;
	(x :number) :string;
	new (x :number) :I1;
	[key :string] :unknown;
	readonly p3 :string;
}
type T1 = (x :number)=>void;
type T2 = (x: number) =>void;
type T3 = (x: number)=> void;
type T4 = new (x :number)=>C1;
type T5 = abstract new () =>  C2;
type T6 = { [K in keyof I1] :I1[K] };
type T7 = { [K in keyof I1] ?:I1[K] };
type T8 = { [K in keyof I1] ?: I1[K] };
type T9 = { [K in keyof I1]-?:I1[K] };
type T10 = { [K in keyof I1] +?:I1[K] };
type T11 = { readonly [K in keyof I1]  -?: I1[K] };
let b1 :(string);
let b2:((number));
let b3 : (() => void);
function g1(x: unknown) :x is string { return true; }
function g2(x: unknown) :asserts x is string {}
function g3(this :Window, x :number) {}
function g4({ a } :{ a: number }, [b] :[number], ...rest :number[]) {}
declare function g5(x :number) :void;
try {} catch (e :unknown) {}
let c1 /* comment */ : string;
let c2: /* comment */string;
let c3 :/* comment */ string;
let c4
	: string;
let c5:
	string;
function h1(x
	:number) {}
const o1 = { m(x :number) :void {} };
for (const d1 of [] as number[]) {}
export const e1 = (x? : number) :void => {};
let i1: { a :number; b ? : string };
