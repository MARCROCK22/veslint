declare const value: number;
declare const error: Error;
declare const promise: Promise<number>;

// Fixed.
async function a1() { return Promise.resolve(value); }
async function a2() { return Promise.reject(error); }
const a3 = async () => Promise.resolve(value);
const a4 = async () => Promise.reject(error);
async function* a5() { yield Promise.resolve(value); }
async function* a6() { yield Promise.reject(error); }
async function a7() { return Promise.resolve(); }
async function a8() { return Promise.reject(); }
const a9 = async () => Promise.resolve({ a: 1 });
async function a10() { return await Promise.resolve(value); }
const a11 = promise.then(() => Promise.resolve(value));
const a12 = promise.catch(() => Promise.reject(error));
const a13 = async () => Promise.resolve((value, 1));

// Reported, not fixed.
async function b1() { try { return Promise.reject(error); } catch { return 1; } }
async function b2() { return Promise.resolve(value, 1 as never); }
async function b3() { return Promise.resolve(/* c */ value); }
async function* b4() { const x = yield Promise.reject(error); return x; }

// Not reported.
function k1() { return Promise.resolve(value); }
async function k2() { return promise; }
function* k3() { yield Promise.resolve(value); }
const k4 = promise.then(function* () { yield Promise.resolve(value); });
async function* k5() { yield* Promise.resolve([1]) as never; }
export { a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, b1, b2, b3, b4, k1, k2, k3, k4, k5 };
