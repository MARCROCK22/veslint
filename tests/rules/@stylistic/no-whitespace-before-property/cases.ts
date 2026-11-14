declare const foo: { bar: { baz: number[] }; 'q-r': number; fn(): void } | undefined;
declare const arr: number[];
declare namespace Space {
	namespace Inner {
		type T = string;
	}
	const value: number;
}

const a = foo !.bar;
const b = foo! . bar .baz;
const c = foo ?.bar;
const d = foo ?. [ 'q-r' ];
const e = arr [0];
const f = (arr) [1];
const g = arr
	.length;
const h = foo!./* c */ bar;
const i = foo! /* c */.bar;
const j = foo! // line
	.bar;
const k = 5 .toString();
const l = 5.5 .toFixed();
const m = 0x10 .toString();
const n = foo! [ 'q-r' ];
const o = arr [arr [0]!];
const p = foo?.bar .baz;
const q = (foo) ?.fn();

class Box {
	#secret = 1;
	read(other: Box) {
		return other .#secret + this .#secret;
	}
}

type R = Space .Inner .T;
type S = (typeof arr) [number];
type U = typeof Space .value;
type V = Array<string> ['length'];
type W = import('./other') .Thing;
type X = typeof import('./other') .thing;
type Y = Space/* c */ .Inner.T;
import Alias = Space .Inner;
namespace Outer .Nested {
	export const z = 1;
}

export { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, Box, Alias, Outer };
export type { R, S, U, V, W, X, Y };
