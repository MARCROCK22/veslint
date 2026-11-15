// Reported: an empty class body on more than one line.
class A {
}

class B {

}

class C {    
	
}

export default class {
}

const D = class {
};

abstract class E {
}

declare class F {
}

class G extends A {
}

class H implements I {
}

class J<T> {
}

namespace N {
	export class K {
	}
}

function f() {
	return class {
	};
}

@decorate
class L {
}

// Not reported: on one line, with a member, with a comment inside.
class M {}
class O { }
class P {
	x = 1;
}
class Q {
	// a comment
}
class R {
	/* a comment */
}
class S { /* a comment */ }
class T {
	;
}
class U {
	static {}
}
interface I {
}
type V = {
};
const W = {
};
enum X {
}

declare const decorate: ClassDecorator;
export { D, E, F, G, H, J, L, M, O, P, Q, R, S, T, U, V, W, X, f };
