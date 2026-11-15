import a from "a"
import { b } from "b";
import c = require("c")
import * as d from "d";
export * from "e"
export { a, b }
export type T = string
type U = number;
declare function df(): void
declare function dg(): void;
let x = 1
let y = 2;
var z = 3, w = 4
for (let i = 0; i < 1; i++) {}
for (const k in {}) {}
for (const k of []) {}
function f() {
  if (x) return
  if (y) return x;
  throw new Error()
}
do x++; while (x < 3)
do { x++ } while (x < 3);
while (x) { break }
while (x) { continue; }
debugger
label: for (;;) { break label }
x++
;[1].forEach(f)
const g = () => {}
const h = () => { return 1 }
export default x
class K {
  a = 1
  b = 2;
  get;
  set = 1
  static static
  accessor acc = 1
  m(): void
  m(x?: number): void {}
  [key: string]: unknown
}
export abstract class L {
  abstract p: number
  abstract q: string;
  abstract m(): void
}
if (x) { x++ } else { y++; }
{ x++; y++ }
class M { a = 1; b = 2 }
class N { static { x++ } }
class O { static { x++; } }
export = x
f() // comment
f() /* comment */
x = `a${x}`
y = 'ü'
'use strict'
f()