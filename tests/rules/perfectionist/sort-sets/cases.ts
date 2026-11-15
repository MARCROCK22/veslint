declare const value: string;
declare const x: string[];
declare const o: { a: string; b: string };
// Reported and fixed.
new Set(['b', 'a']);
new Set(['c', 'b', 'a']);
new Set([b, a, ...x, d, c]);
new Set(['B', 'a', 'C']);
new Set([10, 9, 1, 100]);
new Set([
  'b', // about b
  'a', // about a
]);
new Set([
  // above b
  'b',
  /* above a */
  'a',
]);
new Set([
  'b' /* after b */,
  'a',
]);
new Set(['b', , 'a']);
new Set([('b'), ('a')]);
new Set([true, false, null, 1n, /b/, /a/g]);
new Set([`b`, `a`]);
new Set([o.b, o.a]);
new Set(['a b', 'a  a']);
new Set(['_b', '-a', 'a']);
// Not reported.
new Set(['a', 'b']);
new Set(['a']);
new Set([]);
new Set([...x, ...x]);
new Set([a, ...x, 'b']);
// Disabled.
new Set([
  'c',
  // eslint-disable-next-line perfectionist/sort-sets
  'a',
  'b',
]);
new Set(['b', 'a'], x);
new Set([...x], ['b', 'a']);
new Set(['b', 'a'] as string[]);
new WeakSet([{}, {}]);
['b', 'a'].includes(value);
new Set(new Array('b', 'a'));
new Set<string>(['b', 'a']);
