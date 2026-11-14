declare const pairs: [string, number][];
declare const entries: Iterable<[string, number]>;
declare const _: {fromPairs: (value: unknown) => unknown};
declare const lodash: {fromPairs: (value: unknown) => unknown};
declare const key: string;
declare const value: number;

// `Array#reduce()` with `Object.assign()`
pairs.reduce((object, [key, value]) => Object.assign(object, {[key]: value}), {});
pairs.reduce((object, pair) => Object.assign(object, {[pair[0]]: pair[1]}), {});
pairs.reduce(object => Object.assign(object, {key}), {});
pairs.reduce((object) => Object.assign(object, {key: value}), {});
pairs.reduce((object: Record<string, number>, [key, value]) => Object.assign(object, {[key]: value}), {});
pairs.reduce<Record<string, number>>((object, [key, value]) => Object.assign(object, {[key]: value}), {});
pairs.reduce((object, [key, value]) => Object.assign(object, {[key]: value}), ({}));
pairs.reduce((object, [key, value]) => Object.assign(object, {'quoted': value}), {},);
pairs.reduce((object, [key, value]) => Object.assign(object, {1: value}), {});

// `Array#reduce()` with a spread
pairs.reduce((object, [key, value]) => ({...object, [key]: value}), {});
pairs.reduce((object, [key, value]) => ({...object, key: (value)}), {});
pairs.reduce((object, [key, value]) => (({...object, [(key)]: value})), {});
const fromSpread = pairs.reduce((object, [key, value]) => ({...object, [key]: value as number}), {});

// Comments keep the report without a fix
pairs.reduce((object, [key, value]) => ({...object, /* keep */ [key]: value}), {});
pairs.reduce((object, [key, value]) => ({...object, [key]: value}), /* keep */ {});
pairs.reduce((object, [key, value]) => ({...object, [key]: value}) /* keep */, {});

// Not reported
pairs.reduce((object, [key, value]) => ({...object, [key]: value, extra: 1}), {});
pairs.reduce((object, [key, value]) => ({...object, [key]: object.length}), {});
pairs.reduce(async (object, [key, value]) => ({...object, [key]: value}), {});
pairs.reduce(function (object, [key, value]) { return {...object, [key]: value}; }, {});
pairs.reduce(({...object}, [key, value]) => ({...object, [key]: value}), {});
pairs.reduce((object, [key, value]) => ({...other, [key]: value}), {});
pairs.reduce((object, [key, value]) => Object.assign(other, {[key]: value}), {});
pairs.reduce((object, [key, value]) => ({...object, get [key]() { return value; }}), {});
pairs.reduce((object, [key, value]) => ({...object, [key]() {}}), {});
pairs.reduce((object, [key, value]) => ({...object, __proto__: value}), {});
pairs.reduce((object, [key, value]) => ({...object, ['__proto__']: value}), {});
pairs.reduce((object, [key, value]) => ({...object, [key]: value}), {} as Record<string, number>);
new Uint8Array([1, 2]).reduce((object, value) => ({...object, [value]: value}), {});
declare const other: object;

// `for…of` loops
function loops() {
	const object = {};
	for (const [key, value] of pairs) {
		object[key] = value;
	}

	const second: Record<string, number> = {};
	for (let [key, value] of entries) second[key] = value;

	const third = {};
	for (const [key, value] of (pairs)) third[key] = value;
	console.log(object, second, third);
}

function loopsWithComments() {
	const object = {};
	// keep
	for (const [key, value] of pairs) {
		object[key] = value;
	}

	const second = {};
	for (const [key, value] of pairs) {
		second[key] = value; // keep
	}
	console.log(object, second);
}

function loopsNotReported() {
	const first = {};
	for await (const [key, value] of pairs) first[key] = value;

	const second = {};
	for (const [key, value] of pairs) second[value] = key;

	const third = {};
	for (const [key, value] of [third]) third[key] = value;

	const fourth = {}, other = {};
	for (const [key, value] of pairs) fourth[key] = value;

	const fifth = {};
	for (const [key, value] of pairs) { fifth[key] = value; console.log(key); }

	const sixth = {};
	for (const [key, value] of pairs) sixth[key] += value;

	const seventh = {};
	for (const [key, value] of pairs) seventh.key = value;

	var eighth = Object.create(null);
	for (const [key, value] of pairs) eighth[key] = value;

	const ninth = {};
	for (const [ninth, value] of pairs) other[ninth] = value;

	const tenth = {};
	for (const pair of pairs) tenth[pair[0]] = pair[1];
	console.log(first, second, third, fourth, other, fifth, sixth, seventh, eighth, ninth, tenth);
}

function varLoop() {
	var object = {};
	for (const [key, value] of pairs) object[key] = value;
	return object;
}

function needsSemicolon() {
	let object = {}
	for (const [key, value] of pairs) object[key] = value
	;[object].forEach(console.log)
}

function sameLine() {
	const object = {}; for (const [key, value] of pairs) object[key] = value; return object;
}

// Functions
_.fromPairs(pairs);
lodash.fromPairs(pairs);
_.fromPairs(...pairs);
_.fromPairs(pairs, extra);
_?.fromPairs(pairs);
_.fromPairs?.(pairs);
new _.fromPairs(pairs);
fromPairs(pairs);
declare const extra: unknown;
declare function fromPairs(value: unknown): unknown;

export {};
