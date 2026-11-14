declare const it: IteratorObject<number>;
declare const pairs: IteratorObject<[string, number]>;

// Fixed.
const a1 = new Set(it.toArray());
const a2 = new Map(pairs.toArray());
const a3 = new Uint8Array(it.toArray());
const a4 = Array.from(it.toArray());
const a5 = Object.fromEntries(pairs.toArray());
const a6 = [...it.toArray()];
const a7 = Math.max(...it.toArray());
const a8 = new Set((it).toArray());

// Suggestions.
const b1 = Array.from(it.toArray(), x => x * 2);
const b2 = Promise.all(it.toArray());
for (const x of it.toArray()) { console.log(x); }
function* g1() { yield* it.toArray(); }
const b3 = it.toArray().every(x => x > 0);
const b4 = it.toArray().some(x => x > 0);
const b5 = it.toArray().find(x => x > 0);
it.toArray().forEach(x => console.log(x));
const b6 = it.toArray().reduce((a, b) => a + b, 0);
const b7 = new Uint8Array(it.toArray(), 0);

// No fix (a comment).
const c1 = new Set(it/* c */.toArray());

// Not reported.
const k1 = [1, 2].toArray?.();
const k2 = it.toArray().map(x => x);
const k3 = it.toArray().every((x, i, all) => all.length > i);
const k4 = it.toArray().reduce((a, b, i, all) => a + all[i], 0);
const k5 = it.toArray().every(function () { return arguments.length > 0; });
const k6 = it.toArray().every(x => x > 0, null);
const k7 = it?.toArray();
const k8 = new Set(it.toArray(1 as never));
class Vec { toArray() { return [1]; } }
const k9 = new Set(new Vec().toArray());
const vec = new Vec();
const k10 = new Set(vec.toArray());
const k11 = { a: [...it.toArray()] }.a;
export { a1, a2, a3, a4, a5, a6, a7, a8, b1, b2, g1, b3, b4, b5, b6, b7, c1, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11 };
