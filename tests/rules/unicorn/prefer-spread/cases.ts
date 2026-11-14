declare const values: number[];
declare const tuple: [number, string];
declare const readonlyValues: readonly string[];
declare const set: Set<number>;
declare const map: Map<string, number>;
declare const text: string;
declare const unknownValue: unknown;
declare const anyValue: any;
declare const maybe: number[] | undefined;
declare const mixed: number[] | string;
declare const object: { array: number[]; other: string };
declare function call(...args: unknown[]): unknown;
declare function getArray(): number[];
declare class Box {
	concat(other: Box): Box;
	slice(): Box;
}
declare const box: Box;
interface Chain {
	concat(next: Chain): Chain;
}
declare const chain: Chain;
type Alias = string[];
declare const aliased: Alias;
declare const buffer: Buffer;

// `Array.from()`: a fix when it initializes an unannotated variable with a copy of the same type.
const fromFixed = Array.from(values);
const fromSet = Array.from(set);
const fromText = Array.from(text);
call(Array.from(set));
Array.from(map).forEach(call);
const fromHoles = Array.from([1, , 3]);
const fromLiteral = Array.from([1, 2]);
const fromComment = Array.from(/* keep */ set);
const fromCommentOutside = Array.from(set /* drop */);
const fromParenthesized = Array.from((values));

// `Array.from()` that is not reported.
const fromLength = Array.from({ length: 3 });
const fromRange = Array.from(Array(3).keys());
const fromNumber = Array.from(5);
const fromBuffer = Array.from(new ArrayBuffer(8));
const fromConcat = Array.from([...values, ...set]);
const fromTwo = Array.from(set, call);
const fromTyped = Uint8Array.from(set);

// `Array#concat()` on known arrays.
const concat1 = values.concat(1);
const concat2 = values.concat([1, 2]);
const concat3 = [1, 2].concat(values, [3]);
const concat4 = [1, 2,].concat([3,], 4);
const concat5 = [].concat(values);
const concat6 = values.concat();
const concat7 = tuple.concat(readonlyValues);
const concat8 = aliased.concat('a');
const concat9 = (values as number[]).concat(2);
const concat10 = [1, , 3].concat([4, , 6]);
const concat11 = values.concat(call());
const concat12 = values.concat(...[1, 2]);
const concat13 = values.concat(`a`, 'b');
const concat14 = readonlyValues.concat(['x'] as const);
let concat15 = values
concat15.concat(1);
const concat16 = values.concat(getArray(), 1);
const concat17 = values.concat(1, getArray());
const concat18 = values.concat(Array(3));
const concat19 = values.concat(/* keep */ 1);
const concat20 = values.concat([1, /* keep */], [2]);
const concat21 = values.concat(([/* inside */ 1]));

// `Array#concat()` on receivers that may or may not be arrays.
function concatUnknown(input: any, other: unknown) {
	input.concat(other);
	input.concat('a', 'b');
	input.concat(1, other, [2]);
	other.concat(anyValue);
	anyValue.concat(input, ...values);
	maybe.concat(1);
	mixed.concat(2);
}
function concatTyped<T extends unknown[]>(array: T, readonly: ReadonlyArray<number>, both: number[] & { tag: true }) {
	array.concat(1);
	readonly.concat(2);
	both.concat(3);
}
function concatIsArray(input: unknown) {
	if (Array.isArray(input)) {
		input.concat(1);
	} else {
		input.concat(2);
	}
	if (!Array.isArray(input)) {
		input.concat(3);
	}
}

// `Array#concat()` that is not reported.
text.concat('a');
box.concat(box);
chain.concat(chain);
buffer.concat;
Buffer.concat([buffer]).concat(buffer);
object.other.concat('x');
String(1).concat('2');
(() => {}).concat;
function concatInLoop(items: number[][]) {
	let result: number[] = [];
	for (const item of items) {
		result = result.concat(item);
	}
	return result;
}

// `Array#slice()`.
const slice1 = values.slice();
const slice2 = values.slice(0);
call(values.slice());
const slice3 = getArray().slice();
const slice4 = object.array.slice();
const slice5 = (values).slice();
const slice6 = values.slice(/* keep */);
const slice7 = values?.slice();
const slice8 = tuple.slice();

// `Array#slice()` that is not reported.
values.slice(1);
values.slice(0, 1);
text.slice();
[1, 2].slice();
new Uint8Array(2).slice();
Box.slice();
this.slice();
object?.array.slice();
values.join(',').slice();

// `Array#toSpliced()`.
const spliced1 = values.toSpliced();
call(values.toSpliced());
const spliced2 = readonlyValues.toSpliced();

// `Array#toSpliced()` that is not reported.
values.toSpliced(0);
text.toSpliced();
[1].toSpliced();
new Uint8Array(2).toSpliced();

// Semicolons.
const semicolon = 1
Array.from(set).forEach(call)
const semicolon2 = 2
values.slice().forEach(call)

// `for…of` copies.
function forOf1(source: Iterable<number>) {
	const result = [];
	for (const value of source) {
		result.push(value);
	}
	return result;
}
function forOf2(source: Set<string>) {
	let result: string[] = [];
	for (const value of source) result.push(value);
	return result;
}
function forOf3(source: number[]) {
	const result = [];
	for (const [index, element] of source.entries()) {
		result[index] = element;
	}
	return result;
}
function forOf4(source: number[]) {
	const result: number[] = [];
	const read = () => result.length;
	for (const value of source) {
		result.push(value);
	}
	return read;
}
function forOf5(source: number[]) {
	const result = [];
	for (const value of source) {
		// keep
		result.push(value);
	}
	return result;
}
function forOf6(source: number[]) {
	const result = [];
	for (const value of (/* keep */ source)) {
		result.push(value);
	}
	return result;
}
function forOf7(source: number[]) {
	const result = [];
	for (const value of source) {
		result.push(helper());
	}
	function helper() {
		return result.length;
	}
	return result;
}

// `for…of` loops that are not reported.
async function forOfNot(source: number[], other: number[][]) {
	const a = [];
	for await (const value of source) {
		a.push(value);
	}
	const b = [];
	for (const value of source) {
		b.push(value);
		call(value);
	}
	const c = [];
	for (const c2 of c) {
		c.push(c2);
	}
	const d = [1];
	for (const value of source) {
		d.push(value);
	}
	const e = [];
	for (const [index, element] of unknownValue.entries()) {
		e[index] = element;
	}
	const f = [];
	for (const value of other[f.length]) {
		f.push(value);
	}
}

// needsSemicolon of 79: the statement before ends without a semicolon.
let semicolonCounter = 0
semicolonCounter++
Array.from(new Set([semicolonCounter])).forEach(item => item)
