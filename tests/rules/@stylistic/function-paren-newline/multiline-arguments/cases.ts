declare function call(...args: unknown[]): void;
declare function generic<T>(...args: T[]): void;
declare class Klass { constructor(...args: unknown[]); }

function oneLine(a: number, b: number) {}
function multi(a: number,
	b: number) {}
function wrapped(
	a: number,
	b: number,
) {}
function leftOnly(
	a: number, b: number) {}
function rightOnly(a: number, b: number
) {}
function none() {}
function emptyBroken(
) {}
function single(
	a: number,
) {}
function typed<T extends Array<number>>(a: T,
	b: T) {}
function commented(/* c */
	a: number, b: number) {}
function commented2( // line
	a: number, b: number) {}

const expression = function (a: number,
	b: number) {};
const arrow = (a: number,
	b: number) => a + b;
const arrowSingle = a => a;
const arrowAsync = async (a: number,
	b: number) => a + b;
const arrowGeneric = <T,>(a: T,
	b: T) => a;
const arrowEmpty = (
) => 1;

call(1, 2);
call(1,
	2);
call(
	1, 2);
call(1, 2
);
call(
	1,
	2,
);
call();
call(
);
call(() => {
	return 1;
});
call((1),
	2);
generic<number>(1,
	2);
generic<Array<number>>(1,
	2);
(call)(1,
	2);
call?.(1,
	2);
new Klass(1,
	2);
new Klass;
new Klass();
new Klass(
);
const lazy = import('./mod',
	{ with: { type: 'json' } });
const lazy2 = import(
	'./mod');

class Methods {
	method(a: number,
		b: number) {}
	constructor(
		a: number, b: number) {}
}
const obj = {
	method(a: number,
		b: number) {},
};
call(1, 2,
	3, 4);
call(1,
	2, 3);
