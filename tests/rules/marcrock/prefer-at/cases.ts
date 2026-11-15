declare const array: number[];
declare const other: number[];
declare const string: string;
declare const some: { string: string; array: number[] };
declare const unknownValue: any;
declare const _: { last<T>(a: readonly T[]): T | undefined };
declare const lodash: typeof _;
declare const underscore: typeof _;

// Negative index: reported and fixed.
array[array.length - 1];
array[array.length - 2];
array[array.length -  1];
array[array.length - 1.5];
array[array.length - 0x1];
array[(array.length) - 1];
array[array.length - 1 - 1];
array?.[array.length - 1];
some.array[some.array.length - 1];
some['array'][some.array.length - 1];
some.array[some['array'].length - 1];
(array as number[])[array.length - 1];
array[(array as number[]).length - 1];
array![array.length - 1];
array[array.length /* c */ - 1];
array[ array.length - 1 ];
const x1 = array[array.length - 1] + other[other.length - 3];
function foo1() {
	return arguments[arguments.length - 1];
}
declare const s1: string;
s1[s1.length - 1];

// Negative index: not reported.
array[array.length + 1];
array[array.length - 0];
array[array.length - -1];
array[other.length - 1];
array[array.length];
array[array?.length - 1];
array[array['length'] - 1];
array[array.length - 1] = 1;
array[array.length - 1] += 1;
array[array.length - 1]++;
--array[array.length - 1];
delete array[array.length - 1];
[array[array.length - 1]] = [1];
({ a: array[array.length - 1] } = { a: 1 });
array.length - 1;
array[0];
array[1];
array.at(-1);

// Present elements: not reported.
declare const t1: readonly [string, number];
t1[t1.length - 1];
t1[t1.length - 2];
declare const t2: [string, number];
t2[t2.length - 1];
declare const t3: readonly [string, number?];
t3[t3.length - 1];
const t4 = [1, 2, 3] as const;
t4[t4.length - 3];
const a1 = [1, 2, 3];
a1[a1.length - 1];
const str1 = 'abc';
str1[str1.length - 1];
const tpl1 = `abc`;
tpl1[tpl1.length - 2];
[1, 2][[1, 2].length - 1];
function g1(r: string[]) {
	if (r.length < 2) {
		return;
	}
	return r[r.length - 2];
}
function g2(r: string[]) {
	if (!r.length) return;
	return r[r.length - 1];
}
// Present elements: still reported.
declare const t5: [string?];
t5[t5.length - 1];
declare const t6: readonly [string, number];
t6[t6.length - 3];
function g3(r: string[]) {
	if (r.length < 2) return;
	return r[r.length - 3];
}
function g4() {
	const t: [string, number] = ['a', 1];
	t.pop();
	return t[t.length - 1];
}
const a2 = [1];
a2.push(2);
a2[a2.length - 1];
declare const t7: [string, number] | readonly [boolean];
t7[t7.length - 1];
t7[t7.length - 2];
declare const t8: [string, ...number[]];
t8[t8.length - 1];

// String#charAt: suggestions.
string.charAt(string.length - 1);
string?.charAt(string.length - 1);
some.string.charAt(some.string.length - 1);
string.charAt((( string.length - 1 )));
string.charAt(string.length - 5);
string.charAt(string.length - 1 - 1);
string.charAt(string.length - 1.5);

// String#charAt: not reported.
string.charAt(string.length + 1);
string.charAt(9);
string.charAt(unknownValue);
string.charAt?.(string.length - 1);
string.charAt(string.length - 1, 2);
string['charAt'](string.length - 1);
string.charAt(other.length - 1);

// .slice(…): fixes.
array.slice(-1)[0];
array?.slice(-1)[0];
array.slice(-1).pop();
array.slice(-1).shift();
array.slice(-1.0).shift();
array.slice(-9, -8)[0];
array.slice(-9, -8).pop();
array.slice(-9, -8).shift();
array.slice(-9, -8,)[0];
(array.slice(-1))[0];
((array).slice(-1)).pop();
array.slice((-9), -8)[0];
// .slice(…): suggestions.
array.slice(-9, unknownValue)[0];
array.slice(-9, unknownValue).shift();
array.slice(-9, -7)[0];
// .slice(…): not reported.
array.slice(-9)[0];
array.slice(-9).pop();
array.slice(-9, -8).pop;
array.slice(-1)[1];
array.slice(-1)?.[0];
array.slice?.(-1)[0];
array.slice(-1).shift?.();
array.slice(-1)?.shift();
array.slice(-1)[0] = 1;
array.slice(1)[0];
array.slice(-1n as any)[0];
array.slice(- -1)[0];
array.slice(-9, -8, 1)[0];
array.slice(-9, unknownValue).pop();

// get-last functions: fixes.
_.last(array);
lodash.last(array);
underscore.last(array);
_.last(new Array<number>());
_.last(new Array<number>);
_.last([1, 2]);
_.last((array));
_.last(array as number[]);
_.last(some.array);
_.last(unknownValue || array);
const x2 = 1
_.last([array])
let x3 = 1;
if (x3) _.last([1]);
for (const item of array) _.last([item]);
// get-last functions: not reported or not fixed.
function foo2() {
	return _.last(arguments as any);
}
function foo3() {
	return _.last(arguments);
}
_.last(array, 2 as never);
_.last(...[array] as [number[]]);
_?.last(array);
_.last?.(array);
_['last'](array);
new (_.last as any)(array);
getLast(array);

// .split(…).at(0): fixed to [0].
'a.b'.split('.').at(0);
const SEP = '.';
'a.b'.split(SEP).at(0);
'a.b'.split('.').at(0)!;
('a.b'.split('.')).at(0);
string.split('-').at(0);
string.split(`-`).at(0);
string.split('a' + 'b').at(0);
// Not reported.
'a.b'.split('').at(0);
'a.b'.split('.').at(1);
'a.b'.split('.').at(-1);
'a.b'.split('.', 2).at(0);
'a.b'.split('.')?.at(0);
'a.b'.split('.').at?.(0);
declare const sep: string;
'a.b'.split(sep).at(0);
array.at(0);
declare const notString: { split(s: string): string[] };
notString.split('.').at(0);
unknownValue.split('.').at(0);
'a.b'.split(/\./).at(0);
'a.b'.split('.').at('0' as any);
'a.b'.split('.').at(0.0);

declare function getLast<T>(a: T[]): T;
export { foo1, foo2, foo3, g1, g2, g3, g4, x1, x2 };
