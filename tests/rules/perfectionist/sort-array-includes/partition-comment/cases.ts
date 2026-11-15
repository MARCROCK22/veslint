declare const value: string;
declare const x: string[];
declare const o: { a: string; b: string };
[
  'b',
  'a',
  // part
  'd',
  'c',
].includes(value);
[
  'b',
  /* part */ 'a',
].includes(value);
[
  'c',
  'b',
  // eslint-disable-next-line perfectionist/sort-array-includes
  'a',
].includes(value);
