// Reported: `this` assigned to an identifier.
const self = this;
let that;
that = this;
var a = 1, b = (this);
let c: unknown;
c ||= this;

function f(this: object) {
	const me = this;
	return me;
}

class K {
	method() {
		const instance = this;
		let other;
		other = this;
		return [instance, other];
	}
}

// Not reported.
const { property } = this;
const [element] = this;
const viaAs = this as unknown;
const nonNull = this!;
const wrapped = [this];
let member: { x?: unknown } = {};
member.x = this;
function g(a = this) {
	return a;
}
class L {
	field = this;
	static other = this;
}
