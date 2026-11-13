// Reported.
let a: number;
console.log(a);
var b;
console.log(b);
function f() {
  let c: string;
  return c;
}

// Not reported.
let d: number;
d = 1;
console.log(d);
let e: number;
let g = 1;
const h = 1;
declare let i: number;
console.log(i);
declare module 'm' {
  let j: number;
}
let k: number;
for (k of [1]) {}
console.log(k);
declare const console: { log(...a: unknown[]): void };
