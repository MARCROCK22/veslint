declare function use(...values: unknown[]): void;
declare const key: string;

function basic() {
	const object = {used: 1, unused: 2, 'quoted': 3, 4: 'four', 0x10: 'hex', [`template`]: 5, ['literal']: 6};
	use(object.used);
}

function nested() {
	const object = {a: {b: 1, c: {d: 2, e: 3}}, f: 4};
	use(object.a.c.d);
}

function wrappers() {
	const object = {a: 1, b: 2} as const;
	const other = {a: 1, b: 2} satisfies Record<string, number>;
	const third = <{a: number; b: number}>{a: 1, b: 2};
	use((object as {a: number}).a, other!.a, third.b);
}

function keys() {
	const object = {1: 'one', '2': 'two', 1n: 'big', [null as never]: 0, __proto__: null, ['__proto__']: 1};
	use(object[1], object['2']);
}

function regexKey() {
	const object = {[/a/ as never]: 1, b: 2};
	use(object.b);
}

function dynamic() {
	const object = {a: 1, b: 2};
	use(object[key]);
}

function calls() {
	const object = {a: 1, b: 2};
	object.a();
	const other = {a: 1, b: 2};
	other.c = 3;
	const third = {a: {b: 1, c: 2}};
	third.a.b = 2;
}

function destructuring() {
	const object = {a: 1, b: 2, c: 3};
	const {a} = object;
	let other = {a: 1, b: 2};
	let x;
	({b: x} = other);
	const rest = {a: 1, b: 2};
	const {...all} = rest;
	const computed = {a: 1, b: 2};
	const {[key]: value} = computed;
	use(a, x, all, value);
}

function methods() {
	const object = {a: 1, method() {}};
	const accessor = {a: 1, get b() { return 1; }};
	const fn = {a: 1, b: function () {}};
	const arrow = {a: 1, b: () => {}};
	use(object.method, accessor.b, fn.b, arrow.b);
}

function annotations(parameter: {a: number; b: string; [key: string]: unknown; method(): void}, plain = {x: 1, y: 2}) {
	const typed: {a: number; b: number} = {a: 1, b: 2} as never;
	let noInit: {a: number; b: number};
	noInit = {a: 1, b: 2};
	use(parameter.a, typed.a, noInit.a, plain.x);
}

function passed() {
	const object = {a: 1, b: 2};
	use(object);
	const spread = {a: 1, b: 2};
	use({...spread});
	const typeQuery = {a: 1, b: 2};
	const copy: typeof typeQuery = {a: 1, b: 2};
	use(copy.a);
}

function unusedVariable() {
	const object = {a: 1};
}

function optional() {
	const object = {a: 1, b: 2};
	use(object?.a);
}

function reassigned() {
	let object = {a: 1, b: 2};
	object = {a: 2, b: 3};
	use(object.a);
}

export const exported = {a: 1, b: 2};
const local = {a: 1, b: {c: 1, d: 2}};
use(local.b.c);

export {basic, nested, wrappers, keys, regexKey, dynamic, calls, destructuring, methods, annotations, passed, unusedVariable, optional, reassigned};
