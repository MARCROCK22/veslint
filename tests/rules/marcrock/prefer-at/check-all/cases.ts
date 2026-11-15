declare const array: number[];
declare const string: string;
declare const unknownValue: any;
declare const g: () => void;

// Index access: reported and fixed.
array[0];
array[1];
array[5 + 9];
const offset = 5;
array[offset + 9];
array?.[0];
array[(0)];
array[ 0 ];
array[0x1];
array[1e1];
array[-0];
const FIRST = 0;
array[FIRST];
const OBJ = { i: 1 } as const;
array[OBJ.i];
string[0];
(array as number[])[0];
array![0];
array[array.length - 1];
function f1() {
	return arguments[0];
}

// Index access: not reported.
array[unknownValue];
array[-1];
array[1.5];
array[1n];
array['0'];
array[NaN];
array[Infinity];
array[1e21 * 1e21];
++array[1];
array[1] = 2;
array[0] ??= 1;
delete array[0];
[array[0]] = [1];
({ a: array[0] } = { a: 1 });
array.at(0);

// String#charAt with checkAllIndexAccess.
string.charAt(9);
string.charAt(unknownValue);
string.charAt(string.length - 1);
string.charAt(...[1] as [number]);

// .split('<non-empty>')[0]: not reported.
'a.b'.split('.')[0];
const SEP = '.';
'a.b'.split(SEP)[0];
string.split(`-`)[0];
''.split('.')[0];
'a.b'.split('.')?.[0];
// still reported
''.split('')[0];
declare const sep: string;
'a.b'.split(sep)[0];
'a.b'.split('.')[1];
'a.b'.split('.', 2)[0];
'a.b'.split?.('.')[0];
class C1 {
	split(_s: string): string[] {
		return [];
	}
}
function f2(c: C1) {
	return c.split(',')[0];
}
function f3(x: any) {
	return x.split(',')[0];
}

// Tuples.
declare const t1: readonly [string, number];
t1[0];
t1[1];
t1[2];
const t2 = [10, 20, 30] as const;
t2[2];
declare const t3: [string, number];
t3[1];
declare const t4: [string, number?];
t4[1];
t4[0];
declare const t5: [string, ...number[]];
t5[1];
t5[0];
declare const pairs: [string, number][];
pairs.map((kv) => kv[0] + kv[1]);
pairs.filter((kv): kv is [string, number] => kv[1] !== undefined);
pairs.forEach((kv) => {
	g();
	kv.push(1);
	return kv[0];
});
declare const t6: readonly [string] | readonly [number, number];
t6[0];
t6[1];
declare const t7: [string] | string[];
t7[0];
function f4() {
	const t: [string, number] = ['a', 1];
	t.pop();
	return t[1];
}
function f5(h: (x: unknown) => void) {
	const t: [string, number] = ['a', 1];
	h(t);
	return t[1];
}
function f6() {
	const t: [string, number] = ['a', 1];
	t[0] = 'b';
	return t[1];
}

// Static lengths.
const a1 = [1, 2];
a1[0];
a1[1];
a1[2];
const a2 = [1, , 3];
a2[0];
a2[1];
const a3 = [1, ...array, 3];
a3[0];
a3[1];
const s1 = 'ab';
s1[1];
s1[2];
const s2 = '😀';
s2[1];
const s3 = `ab`;
s3[1];
const s4 = `a${string}`;
s4[0];
const s5 = ('ab');
s5[1];
const s6: string = 'abc';
s6[2];
[10, 20, 30][1];
[10, 20, 30][3];
'A1'[0];
`A1`[1];
function f7(a: number[]) {
	const all = [0].concat(a);
	return all[0];
}
function f8(a: number[]) {
	const all = a.concat(0);
	return all[all.length - 1] + all[0];
}
function f9(a: number[]) {
	const all = [1, 2].concat(a, [3, 4], 5, ...[]);
	return all[0];
}
function f10(a: number[]) {
	const all = [1, 2].concat(a, [3, 4], 5);
	return all[4] + all[5];
}
function f11() {
	const a = ['x'];
	a.pop();
	return a[0];
}
function f12() {
	let a = 'ab';
	a = '';
	return a[0];
}
function f13() {
	let a = 'ab';
	return a[1];
}
function f14() {
	const a = [1];
	const b = a;
	return a[0] + b.length;
}

// Guards.
function h1(r: string[]) {
	if (!r.length) return;
	return r[0];
}
function h2(r: string[]) {
	if (r.length === 0) return;
	return r[0];
}
function h3(r: string[]) {
	if (r.length < 1) throw new Error();
	return r[0];
}
function h4(s: string) {
	if (!s.length) return;
	return s[0];
}
function h5() {
	const r = 'a.b'.split('.');
	if (!r.length) {
		return;
	}
	return r[0];
}
function h6(r: string[]) {
	if (r.length < 2) return;
	return r[1];
}
function h7(r: string[]) {
	if (r.length <= 2) return;
	return r[2] + r[3];
}
function h8(str: string) {
	if (!str) return '';
	return str[0] + str[1];
}
function h9(str: string) {
	if (str === '') return '';
	return str[0];
}
function h10(str: string) {
	if (!str) return '';
	str = str.trim();
	if (!str) return '';
	return str[0];
}
function h11(str: string) {
	if (!str) return '';
	str = str.trim();
	return str[0];
}
function h12(r: string[]) {
	if (0 === r.length) return;
	return r[0];
}
function h13(r: string[]) {
	if (2 > r.length) return;
	return r[1];
}
function h14(r: string[]) {
	if (2 >= r.length) return;
	return r[2];
}
function h15(a: string[]) {
	if (a.length) {
		return a[0];
	}
	return '';
}
function h16(a: string[]) {
	if (a.length >= 2) {
		return a[1];
	} else {
		return a[0];
	}
}
function h17(s: string) {
	if (s.length > 0) {
		return s[0];
	}
	return '';
}
function h18(a: string[]) {
	if (!a.length) {
		return '';
	} else {
		return a[0];
	}
}
function h19(a: string[], s: string) {
	return (a.length ? a[0] : a[1]) + (s ? s[0] : s[1]);
}
function h20(a: string[]) {
	return (a.length && a[0]) || (a.length || a[0]) || (!a.length || a[0]) || (a.length ?? a[0]);
}
function h21(a: string[], b: boolean) {
	if (!a.length || b) return '';
	return a[0];
}
function h22(a: string[], b: boolean) {
	if (!a.length && b) return '';
	return a[0];
}
function h23(a: string[], w: boolean) {
	if (a.length === 0) return '';
	if (w) {
		return a[0];
	}
	return '';
}
function h24(a: string[]) {
	const has = a.length > 0;
	if (!has) return '';
	return a[0];
}
function h25(a: string[]) {
	let has = a.length > 0;
	has = true;
	if (!has) return '';
	return a[0];
}
function h26(a: string[]) {
	switch (a.length) {
		case 0:
			return '';
		case 1:
			return a[0];
		default:
			return a[1];
	}
}
function h27(a: string[]) {
	switch (a.length) {
		case 0:
			break;
		default:
			return a[0];
	}
	return '';
}
function h28(a: string[]) {
	switch (a.length) {
		case 2: {
			return a[1] + a[2];
		}
		case unknownValue:
			return '';
		default:
			return a[0];
	}
}
function h29(a: string[]) {
	switch (a.length) {
		case 0:
		case 1:
			return '';
		default:
			return a[1];
	}
}
function h30(a: string[]) {
	const FIRST = 0;
	if (!a.length) return '';
	return a[FIRST];
}
function h31(r: string[]) {
	const x = r[0];
	if (!r.length) return;
	return x;
}
function h32(r: string[]) {
	if (!r.length) { }
	return r[0];
}
function h33(r: string[], o: string[]) {
	if (!o.length) return;
	return r[0];
}
function h34() {
	let r = ['a'];
	if (!r.length) return;
	r = [];
	return r[0];
}
function h35(r: { length: number; [k: number]: string }) {
	if (!r.length) return;
	return r[0];
}
function h36(arr: string[]) {
	if (!arr) return;
	return arr[0];
}
function h37(r: string[]) {
	if (r.length > 2) return;
	if (r.length >= 1) return;
	if (r.length !== 0) return;
	if (r.length === 5) return;
	if (r.length) return;
	return r[0];
}
function h38(r: string[]) {
	if (r.length != 0) return;
	if (r.length == 0) return;
	return r[0];
}
function h39(a: number[]) {
	if (a.length) {
		a.pop();
		return a[0];
	}
	return -1;
}
function h40(a: number[]) {
	return (a.length > 0 && (g(), a[0])) || -1;
}
function h41() {
	const a = [1];
	if (!a.length) return -1;
	a['pop']();
	return a[0];
}
function h42(a: string[]) {
	if (!a.length) return '';
	{
		const a: string[] = [];
		return a[0];
	}
}
function h43(a: string[]) {
	if (!a.length) return '';
	return () => a[0];
}
function h44(a: string[]) {
	if (!a.length) return '';
	for (const x of a) {
		if (x) continue;
	}
	while (a) {
		if (!a.length) break;
		return a[0];
	}
	return a[0];
}
function h45(a: string[]) {
	if (!a.length) return '';
	return a[0] + a[a.length - 1];
}
function h46(a: string[]) {
	if (!a.length) return '';
	return a[1 - 1];
}
function h47(a: string | string[]) {
	if (!a.length) return '';
	return a[0];
}
function h48(a: string[]) {
	if (a.length === 3) return a[2];
	if (3 == a.length) return a[2];
	if (a.length !== 0) return a[0];
	return '';
}
function h49(a: string[]) {
	if ('' !== (a as unknown)) return '';
	return a[0];
}
function h50(s: string) {
	if (s !== '') {
		return s[0];
	}
	if ('' != s) {
		return s[0];
	}
	return s[0];
}
function h51(a: string[]) {
	if (a.length > 1.5) return a[1];
	if (a.length > -1) return a[0];
	if (a.length > unknownValue) return a[0];
	return '';
}
class K1 {
	static {
		const a = [1];
		if (a.length < 1) throw 1;
		a[0];
	}
}
label: {
	const a = [1, 2];
	if (!a.length) break label;
	a[1];
}

export { f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, K1 };
export { h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, h12, h13, h14, h15, h16, h17, h18, h19, h20 };
export { h21, h22, h23, h24, h25, h26, h27, h28, h29, h30, h31, h32, h33, h34, h35, h36, h37, h38 };
export { h39, h40, h41, h42, h43, h44, h45, h46, h47, h48, h49, h50, h51 };
