declare const value: string;
declare const x: string[];
declare const o: { a: string; b: string };
[
  'b',
  'topB',
  'a',
  'topA',
  'zEnd',
].includes(value);
[
  'topA',

  'a',

  'last',
].includes(value);
[
  'topA',
  'a',


  'last',
].includes(value);
['topA', 'a'].includes(value);
[
  'topA',

  'topB',
].includes(value);
