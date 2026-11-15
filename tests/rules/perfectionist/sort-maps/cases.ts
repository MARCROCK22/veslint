declare const x: [string, number][];
declare const o: { a: string; b: string };
declare const entry: [string, number];
// Reported and fixed.
new Map([['b', 1], ['a', 2]]);
new Map([[b, 1], [a, 2], [c, 3]]);
new Map([
  ['b', 1], // about b
  ['a', 2], // about a
]);
new Map([
  // above b
  ['b', 1],
  /* above a */
  ['a', 2],
]);
new Map([['b', 1], ['a', 2], ...x, ['d', 1], ['c', 1]]);
new Map([['b', 1], , ['a', 2], ['c', 1]]);
new Map([[o.b, 1], [o.a, 2]]);
new Map([[], ['a', 1]]);
new Map([[, 1], ['a', 1], entry]);
new Map([['B', 1], ['a', 1]]);
new Map([[2, 'two'], [10, 'ten'], [1, 'one']]);
new Map([["b", 1], ['a', 2]]);
new Map([[`b`, 1], [`a`, 2]]);
// Not reported.
new Map([['a', 1], ['b', 2]]);
new Map([['a', 1]]);
new Map([]);
new Map();
new Map(x);
new WeakMap([[o, 1], [entry, 2]]);
new Map<string, number>([['b', 1], ['a', 2]]);
new Map([
  ['c', 1],
  // eslint-disable-next-line perfectionist/sort-maps
  ['a', 1],
  ['b', 1],
]);
