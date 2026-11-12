// `--fix`: the fixes of several rules, the ones that overlap (applied in later passes) and the
// removal of directive comments without use.
declare const p: Promise<number>;
declare const text: string;
declare const maybe: string | undefined;
declare const flag: boolean;
declare function log(...values: unknown[]): void;
(void 0);
const a = text.includes('x');
const b = text.startsWith("abc");
const c = text;
const d = flag;
const e = maybe!;
type U = string   | number;
function g(x: number = undefined as never, { y } = { y: 1 }) {
  return [x, y];
}
/b/.exec(text);
 
const unused = 1;
const h = text;
const i = `${flag}`;
const j = !(!text.includes('x'));
/* eslint-disable-next-line @typescript-eslint/no-floating-promises */
p;
p;  
const emoji = '😀'; const k = 'ñ' + (maybe!);
namespace Outer {
  export const value = 1;
  export const twice = value * 2;
}
log(a, b, c, d, e, g, unused, h, i, j, emoji, k, Outer, undefined as U | undefined);
p;
// Rules whose fixes meet: an assertion inside a chain, a returned await, bracket access.
declare const deep: { a?: { b?: { c: string } } } | undefined;
declare const record: { name: string; value: number };
const l = deep?.a?.b?.c;
const m = record.name;
const n = (record.value).toFixed(2);
async function o() {
  return p;
}
async function q() {
  try {
    return p;
  } catch {
    return (record.value);
  }
}
function r(list: number[]) {
  return list.reduce<number>((sum, x) => sum + x, 0);
}
class Chain {
  self(): this {
    return this;
  }
}
const s = [1, 2].forEach(x => { log(x); });
const u = () => { log(1); };
function v(): void {
  log(2);
}
log(l, m, n, o, q, r, Chain, s, u, v);

// A surrogate without its pair in the text of a fix is U+FFFD in the file, as Node writes it.
/�/.exec(text);
const w = text.includes('a�');
log(w);
