// Reported: two spaces or more (and tabs) between tokens of a line.
const a  = 1;
const b =		2;
let c = a  +  b;
function f(x:  number,   y: string)  {
  return x  ? y   : "z";
}
const obj = { key:   1, other:  [1,  2] };
class K {
  #priv  = 1;
  m() { return this.  #priv; }
}
const re =  /ab+c/g;
const tpl =  `a${  a  }b`;
const s = "with   spaces";
type T =  string  |  number;
interface I { p:  T; }
import foo from "./foo.json" with  { type:  "json" };
f(1,  "x")  /* short */;
f(1, "x")  /* a comment longer than twelve */;
f(1, "x")  /* first line
   second line */;
f(1, "x")  // line comment
f(1, "x")  // a line comment longer than twelve
f(1, "x")  // ünïcödé ✓✓✓✓✓✓✓✓✓
f(1, "x")  // 😀😀😀😀😀😀😀
/*  a */  const d = 4;
const e = { a:  1 };
const g  =  [1,   2];

// Not reported.
const h = 1;
const i = {
  a: 1,
    b: 2,
};
f(h,
  i);
const j = "a  b";
const k = `  ${h}  `;
export { a, b, c, d, e, g, h, i, j, k, obj, re, s, tpl, foo, K };
export type { T, I };
