declare const value: string;
declare const x: string[];
declare const o: { a: string; b: string };
[
  'b',
  // part one
  'a',
].includes(value);
[
  'b',
  // other
  'a',
].includes(value);
[
  'b',
  /* part */
  'a',
].includes(value);
