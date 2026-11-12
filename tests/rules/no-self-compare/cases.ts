// no-self-compare: a comparison of something with the same tokens.
declare let x: number;
declare const o: { a: number; b: number };
declare function f(): number;

if (x === x) {}
if (x !== x) {}
if (x == x) {}
if (x > x) {}
if (x <= x) {}
if ((x) === x) {}
if (o.a === o.a) {}
if (o['a'] === o['a']) {}
if (f() === f()) {}
if (x /* one */ === /* two */ x) {}
if (x + 1 > x + 1) {}

// Not the same tokens, or not a comparison.
if (o.a === o['a']) {}
if (o.a === o.b) {}
if (x === -x) {}
if ((x as number) === x) {}
if (x! === x!) {}
const sum = x + x;
const and = x && x;
