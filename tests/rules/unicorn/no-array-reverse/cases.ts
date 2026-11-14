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
