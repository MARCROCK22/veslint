declare const value: string;
declare const x: string[];
declare const o: { a: string; b: string };
[
  'topA',

  'topB',
  'a',
  'b',
].includes(value);
[
  'topA',
  'a',

  'b',
].includes(value);
