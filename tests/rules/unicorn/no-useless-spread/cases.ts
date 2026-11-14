declare const foo: number[];
declare const set: Set<number>;
declare const str: string;
declare function call(...args: unknown[]): void;
declare const obj: { a: number };

// Spread in a list (fixed).
const a1 = [...[1, 2], 3];
const a2 = [...[], 1];
const a3 = { ...{ a: 1 }, b: 2 };
call(...[1, 2]);
call(...[1, , 3]);
new Map(...[[1, 2]] as [Iterable<[number, number]>]);
const a4 = [...([1, 2])];
const a5 = { ...{}, b: 1 };

// Spread in a list (not fixed).
const b1 = new Set(...[[1]]);

// Not reported (a prototype setter, super).
const k1 = { ...{ __proto__: null } };
const k2 = { m() { return { ...{ n() { return super.toString(); } } }; } };

// Iterable to array.
const c1 = new Set([...set]);
const c2 = Promise.all([...set]);
const c3 = Array.from([...set]);
const c4 = Object.fromEntries([...new Map<string, number>()]);
for (const x of [...set]) { console.log(x); }
function* g1() { yield* [...set]; }
const c5 = new Uint8Array([...set]);

// Collection constructor.
const d1 = new Set(...(set as unknown as [Iterable<number>]));

// Object.assign.
const e1 = Object.assign({}, { ...obj });
const e2 = Object.assign({}, { ...obj, ...foo });
const e3 = Object.assign({}, { /* c */ ...obj });
const e4 = Object.assign({ ...obj });

// Clone.
const f1 = [...foo.slice()];
const f2 = [...foo.map(x => x)];
const f3 = [...str.split(',')];
const f4 = [...Object.keys(obj)];
const f5 = [...Array.from(set)];
const f6 = [...new Array(3)];
const f7 = [...foo.concat(1)];
async function f8() { return [...await Promise.all([1])]; }
const f9 = [...str.slice(1)];
function f10() {
  return [
    ...foo.filter(Boolean),
  ];
}
const f11 = [...(foo || []).slice()];
export { a1, a2, a3, a4, a5, b1, k1, k2, c1, c2, c3, c4, g1, c5, d1, e1, e2, e3, e4, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11 };
