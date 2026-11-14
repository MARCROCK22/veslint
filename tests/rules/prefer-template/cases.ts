declare const a: any;
declare const b: any;

// Reported.
const a1 = 'Hello, ' + a + '!';
const a2 = a + 'x';
const a3 = 'x' + a + b;
const a4 = 'x' + (a + b);
const a5 = `x${a}` + b;
const a6 = 'it\'s ' + a;
const a7 = 'a ${b} `c` ' + a;
const a9 = 'x' /* c */ + a;
const a10 = 1 + 'x' + 2;

// Not reported.
const k1 = 'a' + 'b';
const k2 = a + b;
const k3 = `x${a}`;

// A `;` before the template when the statement would continue the line before (10.15.0).
declare function f(): void;
f()
'bar' + a;
a
'bar' + a;
`template`
'bar' + a;
f();
'bar' + a;
if (a) {}
'bar' + a;
const k4 = 'x\\${y}' + a;
