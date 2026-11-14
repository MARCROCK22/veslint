declare function g(): Promise<number>;
declare function h(): number;
let total = 0;
const obj = { a: 0, b: { c: 0 } };
let arr: number[] = [];

// Reported.
async function r1() { total += await g(); }
async function r2() { total = total + await g(); }
async function r3() { obj.a = obj.a + await g(); }
async function r4() { obj.b.c = obj.b.c + (await g()); }
function* r5(): Generator<number, void, number> { total += yield 1; }
async function r6() { const t = total; await g(); total = t + 1; }
async function r7(p: { x: number }) { p.x += await g(); }
async function r8() { arr[0] = arr[0] + await g(); }
const r9 = async () => { total = total + await g(); };
class K {
  async m() { total += await g(); }
}
async function r10() { if (h()) { total += await g(); } }
async function r11() { for (const x of [1]) { total += x + await g(); } }
async function r12() { obj.a += await g(); }

// Not reported.
async function k1() { let local = 0; local += await g(); return local; }
async function k2() { total = await g(); }
async function k3() { const v = await g(); total += v; }
async function k4() { total += h(); }
function k5() { total += h(); }
async function k6() { await g(); total += 1; }
async function k7() { const t = await g(); total = t; }
async function k8() { let x = 0; const f = () => x; x += await g(); return f; }
async function k9() { total = await g() + 1; }
export { r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, K, k1, k2, k3, k4, k5, k6, k7, k8, k9 };
