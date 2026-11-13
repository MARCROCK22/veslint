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
