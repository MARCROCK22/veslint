// Statements, expressions and declarations of the Referencer.
var v1 = 1, v2;
let l1 = v1, l2: number;
const c1 = l1;
{
  var hoisted = c1;
  let inner = hoisted;
  const c2 = inner;
  function inBlock() { return c2; }
  inBlock();
}
function decl(p1: number, p2 = p1, { p3, p4: [p5 = p2] }: any = {}, ...rest: number[]): number {
  var local = p1 + p2 + p3 + p5 + rest.length;
  arguments;
  return local;
}
function early(a = later, b = (() => later)()) { var later = a; return b; }
function dflt(a = arguments) { return a; }
const fe = function named(x: number): number { return x > 0 ? named(x - 1) : 0; };
const anon = function (y = 1) { return y; };
const arrow = (z: number) => z * 2;
const arrowBody = (w = 1) => { return w; };
const arrowParen = (q: number) => (q);
const single = async (s: number) => s;
const bare = b0 => b0;
function* gen(g: number) { yield g; yield* [g]; }
async function asy(t: Promise<number>) { await t; for await (const u of [t]) { u; } }
label: for (var i = 0, n = 10; i < n; i++) { if (i) continue label; else break label; }
for (let j = 0; j < 2; j++) { j; }
for (const k in { a: 1 }) { k; }
for (const [m1, m2 = v1] of [[1, 2]]) { m1; m2; }
for (var o of [1]) { o; }
for (l1 of [1]) {}
for (l1 in {}) {}
for (;;) { break; }
while (v1) { v1--; }
do { ++v1; } while (v1 < 3);
switch (v1) { case c1: let sw = 1; sw; break; default: sw; }
try { throw new Error(); } catch (e) { e; } finally { v1; }
try {} catch ({ message, stack = message }) { stack; }
try {} catch { v1; }
if (v1) v2 = 1; else v2 = 2;
v1 = v2 += 1;
v1 ||= 2; v1 &&= 3; v1 ??= 4;
v1++; --v2;
const obj = { a: v1, [c1]: v2, v1, method(mp: number) { return mp; }, get g() { return 1; }, set s(sv: number) { sv; }, async *am() {}, ...(l2 as any), 'quoted': 1, 2: 3, [`t${v1}`]: 4, fn: function fnKey() { return fnKey; }, arrowProp: () => v1 };
const arr = [v1, ...[v2], , c1];
obj.a = 1; obj['a'] = 2; obj[c1] = 3; obj.method(v1)?.toString(); obj?.[v1]; obj?.method?.(v2);
new Error(obj.a + '');
`tpl ${v1} ${v2}`;
String.raw`x${v1}`;
typeof v1; void v1; delete obj.a; !v1; -v1; v1 in obj; obj instanceof Object;
v1 ? v2 : c1; v1 ?? v2; v1 && v2; (v1, v2);
decl(1); new Map<string, number>(); tagged<number>`a${v1}`; const inst = tagged<string>;
this; import.meta; undefined; NaN; undeclaredGlobal; import('m').then(dyn => dyn);
function tagged<T>(s: TemplateStringsArray, ...subs: unknown[]): T { return s as unknown as T; }
function withTarget() { return new.target; }
const nested = () => () => { var deep = v1; return () => deep; };
const { da, db: { dc = da, ...dr }, [c1]: dd, ...dz } = obj as any, [ea, , eb = ea, ...ez] = arr;
export { decl, early, dflt, fe, anon, arrow, arrowBody, arrowParen, single, bare, gen, asy, inst, withTarget, nested, da, dc, dr, dd, dz, eb, ez, hoisted };
