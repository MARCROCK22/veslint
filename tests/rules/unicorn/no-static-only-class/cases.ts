declare const key: string;
declare const Base: new () => object;
declare function decorate(...args: unknown[]): void;
interface Shape {
	a: number;
}

// Reported, with the fix.
class A {
	static a = 1;
	static b() {
		return 2;
	}
	static c;
	static [key] = 3;
	static get d() {
		return 4;
	}
	static set d(value: number) {
		void value;
	}
	static async e() {}
	static *f() {}
}
export class B {
	static a = 1
	static b() {}
}
const C = class {
	static a = 1;
};
const D = () => class {
	static a = 1;
};
const E = [class { static a = 1; }];
function f() {
	return class
	{
		static a = 1;
	};
}
const G = (class /* c */ {
	static a = 1;
}).a;

// Reported, without the fix.
class H {
	static a = 1;
	static b = this.a;
}
class I {
	static a: number = 1;
}
class J {
	static a = J;
}
class K {
	static [K.name] = 1;
}
abstract class L {
	static a = 1;
}
class M implements Shape {
	static a = 1;
}
const N = class N {
	static a = 1;
};
class O {
	static a = 'super';
}
declare class P {
	static a: number;
}

// Not reported.
class Q {}
class R extends Base {
	static a = 1;
}
class S {
	a = 1;
}
class T {
	static #a = 1;
}
class U {
	static {}
}
class V {
	static readonly a = 1;
}
class W {
	public static a = 1;
}
class X {
	@decorate
	static a = 1;
}
@decorate
class Y {
	static a = 1;
}
class Z {
	[index: string]: unknown;
	static a = 1;
}
class AA {
	static accessor a = 1;
}

export { A, C, D, E, f, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z, AA };

function g() {
	return class // keep
	{
		static value = 1;
	}.value;
}
void g;

export default class {
	static a = 1;
}
