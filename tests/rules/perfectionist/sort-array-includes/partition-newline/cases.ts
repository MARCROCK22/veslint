declare const value: string;
declare const x: string[];
declare const o: { a: string; b: string };
[
  'b',
  'a',

  'd',
  'c',
].includes(value);
[
  'a',

  // comment
  'c',
  'b',
].includes(value);
