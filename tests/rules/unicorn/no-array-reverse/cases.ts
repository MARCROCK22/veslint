// unicorn/no-array-reverse: `.toReversed()` instead of `.reverse()`.
declare const list: number[];

const r1 = list.reverse();
const r2 = [...list].reverse();
const r3 = list?.reverse();
const r4 = [...(list)].reverse();
function f() {
  return list.reverse();
}

// Not reported.
list.reverse();
list?.reverse();
const z1 = list.reverse(1);
const z2 = list.reverse?.();

// 79.0.0: receivers known not to be arrays (by annotation, value or TypeScript type) are left;
// comments in the spread.
declare const set: Set<number>;
declare const map: Map<string, number>;
declare const typed: Uint8Array;
declare const anyValue: any;
const k1 = set.reverse();
const k2 = map.reverse();
const k3 = typed.reverse();
const k4 = anyValue.reverse();
function withSet(s: ReadonlySet<number>) { return s.reverse(); }
const fromSet = new Set([1]);
const k5 = fromSet.reverse();
class Custom { reverse() { return this; } }
declare const custom: Custom;
const k6 = custom.reverse();
const k7 = [.../* keep */ list].reverse();
const k8 = [...list /* keep */].reverse();
const k9 = [...(list as number[])].reverse();
const k10 = [...list ?? []].reverse();
const k11 = [,].reverse();
/** @type {Set<number>} */
const documented = anyValue;
const k12 = documented.reverse();
declare const union: number[] | Set<number>;
const k13 = union.reverse();
declare const strings: readonly string[] | string[];
const k14 = (strings as string[]).reverse();
