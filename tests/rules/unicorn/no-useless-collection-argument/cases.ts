declare const list: number[] | undefined;
declare const pairs: [string, number][] | undefined;

// Reported (and fixed).
const a1 = new Set([]);
const a2 = new Set('');
const a3 = new Set(null);
const a4 = new Set(undefined);
const a5 = new Map([]);
const a6 = new WeakSet([]);
const a7 = new WeakMap(null);
const a8 = new Set(list ?? []);
const a9 = new Map(pairs ?? null);
const a10 = new Set(([]));
const a11 = new Set([],);
const a12 = new Set(`` );
const a13 = new Set((list) ?? []);

// Reported, with a suggestion (a comment).
const b1 = new Set([/* nothing */]);
const b2 = new Set(list ?? /* none */ []);

// Not reported.
const k1 = new Set([1]);
const k2 = new Set(list);
const k3 = new Set(list || []);
const k4 = new Set([], 1 as never);
const k5 = Set([] as never);
const k6 = new Set;
const k7 = new Set(...[[]] as [never[]]);
export { a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, b1, b2, k1, k2, k3, k4, k5, k6, k7 };
