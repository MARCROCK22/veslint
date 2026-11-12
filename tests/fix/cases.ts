// `--fix`: the fixes of several rules, the ones that overlap (applied in later passes) and the
// removal of directive comments without use.
declare const p: Promise<number>;
declare const text: string;
declare const maybe: string | undefined;
declare const flag: boolean;
declare function log(...values: unknown[]): void;
void (void 0);
const a = text.indexOf('x') !== -1;
const b = /^abc/.test(text);
const c = `${text}`;
const d = flag === true;
const e = maybe as string;
type U = string | string | number;
function g(x: number = undefined as never, { y = undefined } = { y: 1 }) {
  return [x, y];
}
text.match(/b/);
// eslint-disable-next-line @typescript-eslint/prefer-includes
const unused = 1;
const h = `${`${text}`}`;
const i = `${flag === true}`;
const j = !(text.indexOf(`${'x'}`) === -1) === true;
/* eslint-disable-next-line @typescript-eslint/prefer-includes, @typescript-eslint/no-floating-promises */
p;
p; // eslint-disable-line @typescript-eslint/no-meaningless-void-operator
const emoji = '😀'; const k = `${'ñ'}` + (maybe as string);
namespace Outer {
  export const value = 1;
  export const twice = Outer.value * 2;
}
log(a, b, c, d, e, g, unused, h, i, j, emoji, k, Outer, undefined as U | undefined);
p;
// Rules whose fixes meet: an assertion inside a chain, a returned await, bracket access.
declare const deep: { a?: { b?: { c: string } } } | undefined;
declare const record: { name: string; value: number };
const l = deep && deep.a && deep.a.b && deep.a.b.c;
const m = record['name'] as string;
const n = (record['value']! as number).toFixed(2);
async function o() {
  return await p;
}
async function q() {
  try {
    return p;
  } catch {
    return await (record['value'] as number);
  }
}
function r(list: number[]) {
  return list.reduce((sum, x) => sum + x, 0 as number);
}
class Chain {
  self(): Chain {
    return this;
  }
}
const s = [1, 2].forEach(x => log(x));
const u = () => void log(1);
function v(): void {
  return log(2);
}
log(l, m, n, o, q, r, Chain, s, u, v);

// A surrogate without its pair in the text of a fix is U+FFFD in the file, as Node writes it.
text.match('\ud800');
const w = /a\udc00/.test(text);
log(w);
