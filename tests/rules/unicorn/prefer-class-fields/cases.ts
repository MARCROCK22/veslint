// Reported, with the fix.
class A {
	constructor() {
		this.a = 1;
	}
	a: number;
}
class B {
	b: string;
	constructor() {
		this.b = 'b';
	}
}
class C {
	c;
	constructor() {
		;
		this.c = `c`;
	}
}
class D {
	private d;
	constructor() { this.d = null; }
}
class E {
	declare x: number;
	#e;
	constructor() {
		this.#e = true;
	}
	other = 1
}
class F {
	f = 0
	constructor() {
		this.f = 2; this.f++;
	}
}

// Reported, with the suggestion.
class G {
	g = 0;
	constructor() {
		this.g = 1;
	}
}

// Reported, without a fix.
class H {
	declare h: number;
	constructor() {
		this.h = 1;
	}
}
class I {
	i!: number;
	constructor() {
		this.i = 1;
	}
}
abstract class J {
	abstract j: number;
	constructor() {
		this.j = 1;
	}
}
class K {
	get k() {
		return 0;
	}
	set k(value) {
		void value;
	}
	constructor() {
		this.k = 1;
	}
}
class L {
	constructor() {
		this.l = /* c */ 1;
	}
	l: number;
}
class M {
	m = 1;
	m = 2;
	constructor() {
		this.m = 3;
	}
}

// Not reported.
class N {
	constructor(private n: number) {
		this.n = 1;
	}
}
class O {
	o: number;
	constructor() {
		this.o += 1;
	}
}
class P {
	p: number;
	constructor(value: number) {
		this.p = value;
	}
}
class Q {
	static q: number;
	constructor() {
		Q.q = 1;
	}
}
class R {
	r: string;
	constructor(suffix: string) {
		this.r = `value${suffix}`;
	}
}

export { A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R };

// Reported, with the fix that adds the field.
export class S {
	constructor() {
		this.s = 1;
	}
}
export class T {
	constructor() {
		this.t = 'x';
	}
	x = 1 }
export const U = class { constructor() { this.u = 2; } };
