// unicorn/require-array-join-separator: `.join()` without its separator.
declare const list: string[];
declare const like: ArrayLike<string>;

const j1 = list.join();
const j2 = [].join.call(like);
const j3 = [].join.call(like,);
const j4 = Array.prototype.join.call(like, );
const j5 = list?.join();
const j6 = list.join(
  // nothing
);

// Not reported.
const z1 = list.join(',');
const z2 = list.join?.();
const z3 = Array.prototype.join.call(like, '');
const z4 = list['join']();

// 79.0.0: a receiver known not to be an array or a typed array (annotations, JSDoc, definitions,
// types) is left alone; `[].join.call(…)` is still reported.
declare const source: unknown;
function k1(values: Set<number>) { return values.join(); }
/** @param {Map<string, number>} values */
function k2(values: any) { return values.join(); }
/** @param {Array<number>} values */
function k3(values: any) { return values.join(); }
function k4(values: Int8Array) { return values.join(); }
function k5(values: Set<number>) { return [].join.call(values); }
/** @type {ReadonlySet<number>} */
const k6: any = source;
const k7 = k6;
k7.join();
const k8 = new Map<string, number>();
(k8 as any).join();
const k9 = new Int8Array();
k9.join();
interface MyList extends Array<number> {}
declare const k10: MyList;
k10.join();
declare const k11: Set<number> | Map<string, number>;
k11.join();
function k12(): Set<number> { return new Set(); }
(k12() as any).join();
