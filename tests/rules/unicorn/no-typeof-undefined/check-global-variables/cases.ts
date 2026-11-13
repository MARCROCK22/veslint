// unicorn/no-typeof-undefined: `typeof x === 'undefined'` becomes `x === undefined`. A global
// variable (declared by the lib or not declared at all) is left alone, unless checkGlobalVariables
// (check-global-variables/), and then it gets a suggestion instead of the fix.
declare let a: unknown;
declare function f(): unknown;

// A variable of the file: reported, with the fix.
const x1 = typeof a === 'undefined';
const x2 = typeof a !== "undefined";
const x3 = typeof a == 'undefined';
const x4 = typeof a != 'undefined';
const x5 = typeof (a) === 'undefined';
const x6 = typeof f() === 'undefined';
const x7 = typeof (a as string) === 'undefined';
function g1(p?: number) {
  return typeof p === 'undefined';
}
function g2(p?: number) {
  return typeof
    p === 'undefined';
}
function g3(p?: number) {
  throw typeof
    p === 'undefined'
}
let y = 1
typeof [a] === 'undefined';

// Globals: only with checkGlobalVariables.
const z1 = typeof window === 'undefined';
const z2 = typeof notDeclared !== 'undefined';
const z3 = typeof globalThis == 'undefined';

// Not reported.
const w1 = typeof a === 'string';
const w2 = 'undefined' === typeof a;
const w3 = typeof a === `undefined`;
const w4 = typeof a > 'undefined';
