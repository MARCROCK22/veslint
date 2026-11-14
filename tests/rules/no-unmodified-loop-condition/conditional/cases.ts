declare function nextOrNull(): boolean;

// With checkConditionalExpressions, each branch of a conditional is checked on its own.
let foo = 0, bar = 1, baz = 2;
while (foo ? bar : baz) { foo += 1; }
let chunk = true, done = false;
while (chunk ? !done : false) { chunk = nextOrNull(); }

// Not reported.
let a = 0, b = 1, c = 2;
while (a ? b : c) { a += 1; b += 1; c += 1; }
let d = 0, e = 1;
while (d < e) { d += 1; }
export {};
