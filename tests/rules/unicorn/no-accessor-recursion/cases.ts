// Reported.
class A {
	private _x = 0;
	get x(): number {
		return this.x;
	}
	set x(value: number) {
		this.x = value;
	}
	get y(): number {
		return this['y'];
	}
	set y(value: number) {
		this[`y`] = value;
	}
	get z(): number {
		const { z } = this;
		return z;
	}
	get w(): number {
		this.w += 1;
		return 0;
	}
	set v(value: number) {
		[this.v] = [value];
	}
	set u(value: number) {
		({ u: this.u } = { u: value });
	}
	set t(value: number) {
		for (this.t of [value]) {
			break;
		}
	}
	get s(): number {
		return (() => this.s)();
	}
	get #p(): number {
		return this.#p;
	}
	set q(value: number) {
		this.q++;
		void value;
	}
}

const o = {
	get a(): number {
		return this.a;
	},
	set a(value: number) {
		this.a = value;
	},
};

// Not reported.
class B {
	private _x = 0;
	get x(): number {
		return this._x;
	}
	set x(value: number) {
		this._x = value;
	}
	get y(): number {
		this.y = 1;
		return 0;
	}
	set z(value: number) {
		void this.z;
		void value;
	}
	get w(): number {
		function inner(this: B): number {
			return this.w;
		}
		return inner.call(this);
	}
	get v(): number {
		class Inner {
			v = this;
		}
		return new Inner() ? 0 : 1;
	}
	get #p(): number {
		return this.p;
	}
	get p(): number {
		return this.#p;
	}
	get ['c'](): number {
		return this.c;
	}
	get m(): number {
		return this![0];
	}
	get n(): number {
		const { n: alias } = (this as B);
		return alias;
	}
	method(): number {
		return this.method();
	}
}

export { A, B, o };
