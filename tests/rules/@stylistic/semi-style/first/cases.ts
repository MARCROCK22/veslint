let a = 1;
let b = 2;
export const e = 5;
export default a;
import * as y from "y";
export * from "z";
function f() {
  if (a) return;
  for (let i = 0;
    i < 1;
    i++) {
    if (i) continue;
    else break;
  }
  debugger;
  throw new Error();
}
do a++;
while (a < 0);
if (a) b++;
else b--;
class K {
  p = 1;
  q = 2;
  static {
    a++;
    b++;
  }
}
switch (a) {
  case 1:
    b++;
    a++;
  default:
    a++;
}
let g = 1; /* c */
let h = 2; // c
export { b, f, g, h, K, y };
