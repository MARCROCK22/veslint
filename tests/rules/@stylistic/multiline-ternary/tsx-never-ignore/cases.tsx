declare const a: boolean;

const x1 = <div>{a ? <span /> : null}</div>;
const x2 = <div>{a
	? <span />
	: null}</div>;
const x3 = <>{a ? 1 : 2}</>;
const x4 = <div>
	{a
		? 1
		: 2}
</div>;
const x5 = a
	? <span />
	: null;

// Nested conditionals whose outermost one is in JSX are ignored too.
declare const b: boolean;
declare const c: boolean;
const n1 = <>
	{a ? <div /> : b ? <div /> : null}
</>;
const n2 = <>
	{a ? <div /> : b ?
		<div /> : null}
</>;
const n3 = <>
	{a ? <div /> : b
		? <div />
		: null}
</>;
const n4 = <div>{a ? b ? 1 : 2 : c ? 3 : 4}</div>;
const n5 = <div>{(a ? b : c) ? <span /> : null}</div>;
// Not in JSX: reported.
const n6 = a ? <div /> : b ? <div /> : null;
const n7 = <div>{[a ? 1 : b ? 2 : 3]}</div>;
export { x1, x2, x3, x4, x5, n1, n2, n3, n4, n5, n6, n7 };
