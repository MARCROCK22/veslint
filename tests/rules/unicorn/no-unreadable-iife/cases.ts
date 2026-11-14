declare const a: boolean, b: number, c: number, baz: () => Promise<number>;

// Reported; r1 to r6 with the suggestion.
const r1 = (() => (a ? b : c))();
const r2 = (() => (
	a ? b : c
))();
const r3 = ((x: number) => ({ x }))(1);
const r4 = (async () => ({ value: await baz() }))();
const r5 = (() => ((b)))();
const r6 = (<T,>(value: T) => (value))(b);
const r7 = (() => (/* inside */ b))();

// Reported without the suggestion (r7 to r9: a comment between the parentheses and the body).
const r8 = (() => (b /* after */))();
const r9 = (() => (
	// leading
	b
))();

// Not reported.
const n1 = ((x: number) => x)(1);
const n2 = (() => {
	return a ? b : c;
})();
const n3 = (function () {
	return b;
})();
const n4 = ((() => b) as () => number)();
const n5 = (() => b);

export { r1, r2, r3, r4, r5, r6, r7, r8, r9, n1, n2, n3, n4, n5 };
