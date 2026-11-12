// How references resolve: the parameters of a function do not see its body, a type reference only
// resolves to a type and a value reference to a value, and each scope resolves what it can.
const v = 1;
function f(p = v, q = () => v) { const v = 2; return [p, q, v]; }
function g(a = b, b = 1) { return a; }
function h(x = arguments, y = h, z = () => arguments) { return [x, y, z]; }
type T = number;
const T = 1;
let t: T = T;
interface OnlyType { a: number }
const useAsValue = OnlyType;
let asType: v;
class K { m(): K { return new K(); } static s = K; }
const fe = function inner(): typeof inner { return inner; };
enum E { A, B = A }
let e: E = E.A, ea: E.A;
namespace N { export const x = 1; export type X = typeof x; }
let n: N.X = N.x;
function outer() { function nested() { return late; } var late = 1; return nested; }
{ let block = 1; { block; } }
let shadow = 1; { let shadow = 2; shadow; } shadow;
try {} catch (shadow) { shadow; }
function typeParams<P, Q extends P>(a: P, b: Q): P { type Local = P | Q; let l: Local = a; return l ?? b; }
class Generic<G> { static s: G; i: G; m<G>(x: G) { return x; } }
function shadowType<T>(x: T) { const T = x; return T; }
import { Imported } from 'm';
let i: Imported = Imported;
function later() { return hoistedFn() + hoistedVar + tdz; }
function hoistedFn() { return 1; }
var hoistedVar = 1;
let tdz = 1;
(function iife(self = iife) { return self; })();
const objWithFn = { fn() { return fn; } };
declare const fn: number;
export { f, g, h, t, useAsValue, asType, K, fe, e, ea, n, outer, typeParams, Generic, shadowType, i, later, objWithFn };
