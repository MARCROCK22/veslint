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
