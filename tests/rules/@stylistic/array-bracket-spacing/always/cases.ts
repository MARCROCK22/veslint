declare const obj: Record<string, unknown>;
declare const items: number[];

const a = [ 1, 2 ];
const b = [1, 2 ];
const c = [ 1, 2];
const d = [];
const e = [ ];
const f = [
	1,
	2,
];
const g = [ /* comment */ 1];
const h = [1 /* comment */ ];
const [ first, second ] = items;
const [third]: number[] = items;
const [ fourth ]: number[] = items;
const i = obj[ 'key' ];
const j = [ , 1];
const k = [[ 1 ], { a: 1 } ];
function l([ x, y ]: [number, number]) {
	return [ x , y ];
}

export {a, b, c, d, e, f, g, h, first, second, third, fourth, i, j, k, l};
