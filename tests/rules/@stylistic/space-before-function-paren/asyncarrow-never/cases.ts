// Spacing before the parentheses of functions and catch clauses.
function f1() {}
function f2 () {}
function f3  /* comment */ () {}
function f4 // comment
() {}
function f5/* comment */() {}
function f6<T>(x: T) { return x; }
function f7<T> (x: T) { return x; }
function f8 <T>(x: T) { return x; }
function* g1() {}
function* g2 () {}
async function a1() {}
async function a2 () {}
const e1 = function() {};
const e2 = function () {};
const e3 = function named() {};
const e4 = function named () {};
const e5 = function*() {};
const e6 = function* () {};
const e7 = function* named() {};
const e8 = async function() {};
const e9 = async function () {};
const e10 = function<T>(x: T) { return x; };
const e11 = function <T> (x: T) { return x; };
const e12 = function named<T>(x: T) { return x; };
const e13 = function named <T> (x: T) { return x; };
const r1 = () => 1;
const r2 = async () => 1;
const r3 = async() => 1;
const r4 = async (x: number) => x;
const r5 = async x => x;
const r6 = async <T>(x: T) => x;
const r7 = async<T> (x: T) => x;
const r8 = async /* comment */ () => 1;
class C1 {
	constructor() {}
	m1() {}
	m2 () {}
	*m3() {}
	async m4 () {}
	get g() { return 1; }
	set s (value: number) {}
	static m5() {}
	[Symbol.iterator] () { return [][Symbol.iterator](); }
	#m6() {}
	m7<T>(x: T) { return x; }
	m8<T> (x: T) { return x; }
	m9 <T>(x: T) { return x; }
	p1 = function () {};
	p2 = async () => 1;
	o1(x: number): void;
	o1 (x: string): void;
	o1(x: unknown) {}
}
abstract class C2 {
	abstract m1(): void;
	abstract m2 (): void;
	abstract m3<T>(): T;
}
const o1 = {
	m1() {},
	m2 () {},
	get g() { return 1; },
	set s(value: number) {},
	p1: function () {},
	p2: function() {},
	p3: function named() {},
	*m3 () {},
	async m4() {},
};
declare function d1(): void;
declare function d2 (): void;
function d3(x: number): void;
function d4 (x: string): void;
function d3(x: unknown) {}
function d4(x: unknown) {}
try {} catch(e) {}
try {} catch (e) {}
try {} catch {}
try {} catch /* comment */ (e) {}
try {} catch
	(e) {}
const n1 = new (function () {} as any)();
export default function () {}
