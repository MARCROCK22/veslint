// The global scope: lib variables (types and values), ESLint's globals for the ecmaVersion, the
// configuration's and the comments'.
/* global fromComment, writableComment: writable, offComment: off, parseInt: off */
/* globals Partial, configOff: readonly, 2, 10: writable, 1 */
/* exported fromComment, Number */
let p: Partial<{ a: number }>;
Partial;
let s: Symbol = Symbol();
let m = new Map<string, NodeListOf<Element>>();
document.title = fromComment + writableComment + offComment + configGlobal + configOff + configWritable;
parseInt('1');
parseFloat('1');
undeclared = 1;
const K = class fromComment {};
const L = class NotDeclared {};
type Q = Awaited<Promise<Record<string, typeof globalThis>>>;
const c = [] as const;
export { p, s, m, K, L, c };
export type { Q };
