/* global foo, Object */
/* global foo:writable */
/*globals bar */
var a: number;
var a: string;
var b = 1, b = 2;
function f1() {}
function f1() {}
function f2(): void;
function f2(x?: number) { return x; }
function f3(p: number) { var p = 1; return p; }
const f4 = (q: number) => { var q: number; return q; };
const f5 = function (r: string) { var r: string; return r; };
interface I1 { a: string }
interface I1 { b: string }
class C1 {}
interface C1 { c: number }
namespace C1 { export const d = 1; }
class C2 {}
class C2 {}
interface C2 {}
function F3() {}
namespace F3 { export const e = 1; }
enum E1 { A }
namespace E1 { export const f = 1; }
enum E2 { B }
enum E2 { C = 2 }
namespace N1 { export const g = 1; }
namespace N1 { export const h = 1; }
namespace N2.N3 { export const i = 1; }
namespace N2.N3 { export const j = 1; }
type T1 = string;
interface T1 {}
{
  var k;
  let l: number;
  { var k; }
  void l;
}
for (let m = 0, m2 = 1; m < 1; m++) { var m2: number; }
for (var n of [1]) { var n: number; }
switch (a) {
  case 1:
    let o = 1;
    void o;
}
try {} catch (e) { var e2; var e2; }
class C3 {
  static { var s; var s; }
  m(t: number) { var t; return t; }
  constructor(private u: number) { var u; void u; }
}
namespace N4 { var v; var v; }
declare global { var w: number; var w: number; }
import { x } from './x';
import { x as y } from './x';
var y;
export { a, b, f1, f2, f3, f4, f5, C1, C2, F3, E1, E2, N1, N2, type T1, C3, N4, x, y, k };
