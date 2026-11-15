declare function call(...args: unknown[]): void;
declare class Klass { constructor(...args: unknown[]); }

call();
call(1);
call(1, 2);
call(1,
	2);
call(
	1,
	2,
);
call(1, 2,
	3);
call(1,
	2, 3);
call((1), (2));
call((1)
	, (2));
call(1, // line comment
	2);
call(1, /* block */ 2);
call(1 /* block */,
	2);
call(() => {
	return 1;
}, 2);
call(function () {
	return 1;
},
2);
new Klass(1, 2);
new Klass(1,
	2);
new Klass;
const lazy = import('./mod', { with: { type: 'json' } });
const lazy2 = import('./mod',
	{ with: { type: 'json' } });
const lazy3 = import('./mod');
call<number>(1, 2);
call?.(1, 2);
call(...[1, 2], 3);
