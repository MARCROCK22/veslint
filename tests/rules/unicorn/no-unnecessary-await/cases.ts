declare function foo(): void;
declare let count: number;

// Fixed (the last thing the function runs).
async function a1() { return await 1; }
async function a2() { await []; }
const a3 = async () => await `x`;
async function a4() { const value = await (count + 1); return value; }
async function a5(flag: boolean) { if (flag) { await 1; } }
async function a6() {
  return await
    [1];
}
async function a7() { foo(); await +1; }

// Reported, not fixed.
async function b1() { await 1; foo(); }
async function b2() { await function () {}; }
async function b3() { await class {}; }
async function b4() { const x = +await 1; return x; }
async function b5() { await (1 as unknown); return 1; }

// Not reported.
async function k1() { await foo(); }
async function k2() { await Promise.resolve(1); }
async function k3() { await count; }
export { a1, a2, a3, a4, a5, a6, a7, b1, b2, b3, b4, b5, k1, k2, k3 };
