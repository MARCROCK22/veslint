/* global foo */
declare let a: any, b: any, c: any, d: any;
declare function call(...args: unknown[]): any;
export const v1 = (a);
export const v2 = (a + b) * c;
export const v3 = ((a + b)) * c;
export const v4 = (a * b) + c;
export const v5 = (a as number) + 1;
export const v6 = (a as number) + (b as number);
export const v7 = (a!) + 1;
export const v8 = (<number>a) + 1;
export const v9 = (a satisfies unknown);
export const v10 = [(a), (b as any), ((c))];
export const v11 = { x: (a), y: ((b)), [(c)]: 1 };
call((a), (b, c), (a = b));
new (call())();
new (a.b)();
new (a().b)();
(call)();
((a as any))();
(function () {})();
(function () {}());
((function () {})());
(() => 1)();
(a?.b)();
(a?.b)?.();
a = (b);
a = (b = c);
(a) = b;
a = (function () {});
export const arrow = () => (a);
export const arrow2 = () => ({ a });
export const arrow3 = () => (a ? b : c);
export const arrow4 = () => (a as any);
export const arrow5 = () => (a = b);
export function ret() { return (a); }
export function ret2() { return (a = b); }
export function ret3() {
  return (
    a
  );
}
export function ret4() { return (/re/); }
export function* gen() { yield (a); yield (a, b); yield ((a)); yield* (a); }
export async function aw() { await (a); await (a as Promise<void>); await (a + b); }
typeof (a);
void (a + b);
!(a as boolean);
(a)++;
++(a);
(a)!++;
throw (a);
if ((a)) {}
if ((a = b)) {}
while ((a)) {}
do {} while ((a));
switch ((a)) { case (b): break; case (c as any): break; }
for ((a) in b) {}
for (a in (b)) {}
for ((a) of b) {}
for (a of (b)) {}
for (a of (b as any)) {}
for ((a); (b); (c)) {}
for ((a in b); ;) {}
for ((a) in (b as any)) {}
for (let i = (a in b) ? 1 : 2; ;) { break; }
for ((function () { return a in b; }); ;) { break; }
(a ? b : c) ? d : a;
a ? (b) : (c);
a ? (b as any) : c;
(a as any) ? b : c;
a ? b : (c as any);
(a || b) ? c : d;
((a, b));
(a, b);
a, (b);
`${(a)}`;
export const spread = [...(a)];
export const spread2 = { ...(a ? b : c) };
export const spread3 = [...(a as any[])];
(a.b);
(a).b;
(a()).b;
(a as any).b;
a[(b)];
a[(b as any)];
(new Date()).getTime();
(new Date).getTime();
(a?.b)!.c;
(1).toString();
(1.5).toString();
(/re/).test('x');
(a?.b)?.c;
('use strict');
export class K extends (a) {}
export class L extends (a as any) {}
export class M extends (a, b) {}
export class N {
  [(a)] = (b);
  [(c)]() {}
  accessor [(d)] = 1;
}
export const { x = (a) } = b;
export const [y = (a)] = b;
[(a)] = b;
({ z: (a) } = b);
[...(a)] = b;
export function params(p = (a)) { return p; }
type T1 = (string);
type T2 = (string | number)[];
type T3 = (string)[];
type T4 = ((string | number))[];
type T5 = (A & B) | C;
type T6 = (A | B) | C;
type T7 = (A) | B;
type T8 = ((A | B)) & C;
type A = string;
type B = number;
type C = boolean;
export const typed: (string) = 'x';
enum E { X = (1), Y = (1 + 2) }
export type { T1, T2, T3, T4, T5, T6, T7, T8 };
export { E };
import((a));
import((a, b));
import(((a, b)));
(async function () {});
(class {});
(function () {});
(let);
const obj = ({ a });
export { obj };
export default (a);
label: (a);
/** @type {number} */ (a);
const jsdoc = /** @type {number} */ (a);
const jsdoc2 = /** @type {number} */ ((a));
const notjsdoc = /* @type {number} */ (a);
const comment = /* keep */ (a);
export { jsdoc, jsdoc2, notjsdoc, comment };
a = (async () => 1);
a ||= (function () {});
a = (class {});
a = (class X {});
(a.call)();
(function () {}).call(a);
(function () {}.call)(a);
(a + b) ** c;
(-a) ** b;
(await a) ** b;
a ** (b ** c);
(a ** b) ** c;
(a && b) ?? c;
a ?? (b || c);
(a) ?? b;
a + (b * c);
a * (b + c);
a - (b - c);
(a - b) - c;
export function ret5() {
  return (
    a + b
  ) * c;
}
export function ret6() {
  return (a
    + b);
}
a = (b, c);
(a, b) ? c : d;
a ? (b, c) : d;
(typeof a)[b];
(a++)[b];
a = +(+b);
a = - (-b);
a = typeof(b);
a = void(0);
a = (b)in c;
