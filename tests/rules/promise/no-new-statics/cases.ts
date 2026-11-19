// promise/no-new-statics: no `new` on the static methods of Promise.
declare const values: Promise<number>[];

const a = new Promise.resolve(1);
const b = new Promise.reject(new Error('x'));
const c = new Promise.all(values);
const d = new Promise.allSettled(values);
const e = new Promise.any(values);
const f = new Promise.race(values);
const g = new Promise.withResolvers<number>();
const h = new  Promise.resolve(2);
const i = new
Promise.resolve(3);
const j = new /* comment */ Promise.resolve(4);
const k = (new Promise.resolve(5));
const l = new Promise.resolve;
const m = new Promise['resolve'](6);
const n = new Promise.something();
const o = Promise.resolve(7);
const p = new Promise((resolve) => resolve(8));
export { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p };
