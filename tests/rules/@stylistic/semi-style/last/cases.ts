let a = 1
;let b = 2;
let c = 3;
let d = 4
;
export const e = 5
;
export default a
;
import x = require("x")
;
import * as y from "y"
;
export * from "z"
;
function f() {
  if (a) return
  ;
  for (let i = 0
    ; i < 1
    ; i++) {
    if (i) continue
    ;
    else break
    ;
  }
  debugger
  ;
  throw new Error()
  ;
}
for (
  ;
  ;
) { break }
do a++
; while (a < 0)
if (a) b++
; else c++
;
class K {
  p = 1
  ;q = 2
  accessor r = 3
  ;
  static {
    a++
    ;
  }
}
switch (a) {
  case 1:
    b++
    ;
  default:
    c++
    ;
}
let g = 1 /* c */
;
let h = 1
; /* c */ let i = 2
label: for (;;) { break label
;}
type T = string
;
interface I { a: string
; }
export { b, c, d, f, g, h, i, K, x, y }
export type { T, I }
;
