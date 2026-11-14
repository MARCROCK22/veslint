declare const items: number[];

const a = [ 1 ];
const b = [1];
const c = [{ a: 1 }, 2, [ 3 ] ];
const d = [ { a: 1 }, 2, [3]];
const e = [[ 1, 2 ], 3, { b: 2 }];
const [ single ] = items;
const [pair, other] = items;

export {a, b, c, d, e, single, pair, other};
