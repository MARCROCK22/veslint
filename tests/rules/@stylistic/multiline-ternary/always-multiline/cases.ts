declare const a: boolean;
declare const b: number;
declare const c: number;

const x1 = a ? b : c;
const x2 = a
	? b
	: c;
const x3 = a ?
	b :
	c;
const x4 = a ? b
	: c;
const x5 = a
	? b : c;
const x6 = (a) ? (b) : (c);
const x7 = (a)
	? (b)
	: (c);
const x8 = a /* comment */ ? b : c;
const x9 = a
	/* comment */ ? b
	: c;
const x10 = a ? b : a ? c : b;
const x11 = a
	? b
	: a
		? c
		: b;
const x12 = (a ||
	a) ? b : c;
const x13 = a ? {
	b,
} : c;
const x14 = a ?
	b
	:
	c;
const x15 = a // line
	? b : c;
