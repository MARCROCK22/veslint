declare const config: { debug: boolean; level: number };
declare const arr: number[];
declare const list: number[];
// Reported.
const a = Math.pow(2, 3);
const b = Math['pow'](2, 3);
({}).__defineGetter__;
const { pow } = Math;
list.forEach(() => {});
const level = config.level;
const { level: l2 } = config;
function f({ pow: p } = Math) {
  return p;
}
// Not reported.
const debug = config.debug;
arr.forEach(() => {});
const c = Math.max(1, 2);
type T = typeof Math.pow;
export { a, b, pow, level, l2, f, debug, c };
export type { T };
