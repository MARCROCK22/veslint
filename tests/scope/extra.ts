// Corners of the Referencer and of the scopes.
declare function d(...args: unknown[]): any;
declare const obj: any, x: any, y: any, z: any;
class Extra {
  #brand = 1;
  static has(o: object) { return #brand in o; }
  static { var sv = 1; sv; }
  static { var sv2 = sv; sv2; }
  field = (() => { var inField = 1; return inField; })();
  [(() => { var inKey = 'k'; return inKey; })()] = 1;
  @(d.e) @d() @d decorated() {}
  usesArguments() { return () => arguments; }
}
function params(a: number, b = a, ...[first, second = b]: number[]) { return [first, second]; }
var redeclared = 1;
var redeclared = 2;
function redeclared2() {}
var redeclared2 = 3;
let fnAndVar = function fnAndVar() { return fnAndVar; };
try {} catch (err) { let inner = err; inner; }
switch (x) { case 1: { var inCase = 1; } default: function inSwitch() { return inCase; } }
if (x) var inIf = 1;
for (var i = 0, j = i; ; ) { break; }
for (const k of [1]) for (const k2 of [k]) k2;
outerLabel: innerLabel: for (;;) { continue innerLabel; }
(function () { 'use strict'; return inIf; })();
import('m', { with: { type: 'json' } });
x?.[y]?.(z); x?.y!.z; x!; (x as any)?.[y as string];
enum Str { 'a-b' = 1, c = Str['a-b'], 'd' = c }
declare module 'mod' { import X from 'x'; export { X }; export const inMod: typeof X; }
namespace Imp { import Alias = Extra; export const v = Alias; export import Again = Alias; }
type G<T> = T extends infer U ? U : never;
type Rec2<T> = { [K in keyof T]: T[K] extends infer V ? V : never };
type Deep<T> = T extends (x: infer A) => (y: infer B) => infer C ? [A, B, C] : T extends { [K in infer D extends string]: infer E } ? [D, E] : never;
function typeGuard(this: unknown): this is string { return true; }
let tupleFn: (...args: [a: string, b?: number]) => void;
let ctorT: new () => Extra;
let obj3: { new (): Extra; (): void; readonly [k: string]: unknown };
const { p = 1, ...others } = obj, [q = p] = obj;
const objLit = { x, y, [z]: z, 'q': q, get acc() { return p; }, set acc(v) { v; }, async *gen(g = others) { yield g; } };
const tpl = `${x}${`${y}`}`, re = /x/g, big = 1n, seq = (x, y), cond = x ? y : z, un = typeof undeclared === 'undefined';
function withInner() { function inner() { return outerVar; } var outerVar = inner; }
export { Extra, params, redeclared, redeclared2, fnAndVar, inSwitch, j, Str, Imp, typeGuard, tupleFn, ctorT, obj3, objLit, tpl, re, big, seq, cond, un, withInner };
export type { G, Rec2, Deep };
