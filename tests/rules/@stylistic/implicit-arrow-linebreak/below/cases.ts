declare function call(...args: unknown[]): void;

const a = () => 1;
const b = () =>
	1;
const c = () => (
	1
);
const d = () =>
	(1);
const e = () =>
	((1));
const f = () => {
	return 1;
};
const g = () =>
{
	return 1;
};
const h = () => // comment
	1;
const i = () => /* comment */
	1;
const j = () =>
	/* comment */ 1;
const k = (x: number) =>
	x * 2;
const l = async () =>
	await Promise.resolve(1);
const m = () =>
	() =>
		1;
const n = (): number =>
	1;
const o = () => ({
	a: 1,
});
const p = () =>
	({ a: 1 });
call(() =>
	1);
const q = () => <const>
	[1];
