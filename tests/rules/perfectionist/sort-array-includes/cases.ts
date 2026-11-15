declare const value: string;
declare const x: string[];
declare const o: { a: string; b: string };
// Reported and fixed.
['b', 'a'].includes(value);
['c', 'b', 'a'].includes(value);
[b, a, ...x, d, c].includes(value);
['B', 'a', 'C'].includes(value);
[10, 9, 1, 100].includes(value);
[
  'b', // about b
  'a', // about a
].includes(value);
[
  // above b
  'b',
  /* above a */
  'a',
].includes(value);
[
  'b' /* after b */,
  'a',
].includes(value);
['b', , 'a'].includes(value);
[('b'), ('a')].includes(value);
[true, false, null, 1n, /b/, /a/g].includes(value);
[`b`, `a`].includes(value);
[o.b, o.a].includes(value);
['a b', 'a  a'].includes(value);
['_b', '-a', 'a'].includes(value);
// Not reported.
['a', 'b'].includes(value);
['a'].includes(value);
[].includes(value);
[...x, ...x].includes(value);
[a, ...x, 'b'].includes(value);
// Disabled.
[
  'c',
  // eslint-disable-next-line perfectionist/sort-array-includes
  'a',
  'b',
].includes(value);
new Array('b', 'a').includes(value);
new Array(2).includes(value);
['b', 'a']?.includes(value);
['b', 'a'].includes?.(value);
['b', 'a'].indexOf(value);
['b', 'a'];
['b', 'a']['includes'](value);
new Set(['b', 'a']);
(['b', 'a']).includes(value);
