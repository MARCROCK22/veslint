declare const value: string;
declare const x: string[];
declare const o: { a: string; b: string };
new Set([
  'b',
  'a',
  // part
  'd',
  'c',
]);
new Set([
  'b',
  /* part */ 'a',
]);
new Set([
  'c',
  'b',
  // eslint-disable-next-line perfectionist/sort-sets
  'a',
]);
