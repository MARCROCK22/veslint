// unicorn/no-typeof-undefined: `typeof x === 'undefined'` becomes `x === undefined`. A global
// variable (declared by the lib or not declared at all) is left alone, unless checkGlobalVariables
// (check-global-variables/), and then it gets a suggestion instead of the fix.
declare function f(): unknown;
let a: unknown = f();

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

// 79.0.0: a template without expressions is a string too.
const x8 = typeof a === `undefined`;

// Not reported.
const w1 = typeof a === 'string';
const w2 = 'undefined' === typeof a;
const w4 = typeof a > 'undefined';

// 79.0.0: an ambient variable is left alone; parentheses where the argument would start a
// statement; a `yield` whose argument starts on the next line keeps `typeof`.
declare const ambient: unknown;
const v1 = typeof ambient === 'undefined';
typeof {value: undefined}.value === 'undefined';
typeof function () {} === 'undefined';
f()
typeof {value: undefined}.value === 'undefined';
const v2 = () => typeof {value: undefined}.value === 'undefined';
function* v3() {
  yield typeof
    a === 'undefined';
}
function v4() {
  return typeof /* keep
  */ a === 'undefined' && true;
}
