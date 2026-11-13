declare const a: any;
declare const b: any;
declare function f(...args: unknown[]): any;
declare const tag: any;

// Reported.
const x1 = f
(a);
const x2 = a
[1];
const x3 = tag
`x`;
const x4 = (a)
(b);
const x5 = a
/ b / g;
declare const g: number;

// Not reported.
const k1 = f(a);
const k2 = f
();
const k3 = a?.
[1];
const k4 = a
  .b;
const k5 = tag`x`;
const k6 = a / b / c;
declare const c: number;
