// Cases of return-await (typescript-eslint 8.62.0, default option 'in-try-catch'). The expected
// findings are in expected.txt, validated against typescript-eslint by
// tests/rules/reference.sh.
declare function task(): Promise<number>;
declare function syncFn(): number;
declare const anyValue: any;
declare const unknownValue: unknown;
declare const thenable: { then(cb: (v: number) => void): void };

// Ordinary context: the returned Promise is not awaited.
async function ordinary() { return task(); }
async function ordinaryAwait() { return await task(); }
async function notPromise() { return await 1; }
async function notPromiseCall() { return await syncFn(); }
async function anyAwait() { return await anyValue; }
async function unknownAwait() { return await unknownValue; }
async function withThenable() { return await thenable; }
async function genericFunction<T extends Promise<number>>(p: T) { return await p; }
async function unconstrainedGeneric<T>(p: T) { return await p; }
async function parens() { return (await task()); }
async function awaitParens() { return await (task()); }
async function logical(c: boolean) { return c && await task(); }
async function emptyReturn() { return; }
async function inSwitch(n: number) { switch (n) { case 1: return await task(); default: return task(); } }

// Error-handling contexts.
async function inTry() { try { return task(); } catch { return 0; } }
async function inTryAwait() { try { return await task(); } catch { return 0; } }
async function inCatch() { try { syncFn(); } catch { return task(); } }
async function inCatchAwait() { try { syncFn(); } catch { return await task(); } }
async function inCatchWithFinally() { try { syncFn(); } catch { return task(); } finally { syncFn(); } }
async function inFinally() { try { syncFn(); } finally { return task(); } }
async function inFinallyAwait() { try { syncFn(); } finally { return await task(); } }
async function nested2() { try { try { syncFn(); } finally { return task(); } } catch { return 0; } }
async function blockInTry() { try { if (syncFn()) { return task(); } } catch { return 0; } return 1; }
async function arrowInTry() {
  try {
    const f = async () => { return task(); };
    return await f();
  } catch {
    return 0;
  }
}

// Conditionals: each branch counts.
async function ternary(c: boolean) { return c ? await task() : task(); }
async function ternaryInTry(c: boolean) { try { return c ? task() : await task(); } catch { return 0; } }
async function ternaryNotPromise(c: boolean) { return c ? await 1 : 2; }
async function nestedTernary(a: boolean, b: boolean) { return a ? (b ? await task() : 1) : await 2; }

// Arrows with an expression body.
const arrow = async () => await task();
const arrowNo = async () => task();
const arrowNotPromise = async () => await 1;
const arrowConditional = async (c: boolean) => c ? await task() : 1;
const noAsync = () => task();

// Functions that are not async, methods and generators.
function noAsyncReturn() { return task(); }
async function nestedNotAsync() { function internal() { return task(); } return internal; }
class SomeClass {
  async method() { try { return task(); } catch { return 0; } }
  get value() { return task(); }
}
const objectValue = { async method() { return await task(); } };
async function* generator() { yield 1; return await task(); }

void [ordinary, ordinaryAwait, notPromise, notPromiseCall, anyAwait, unknownAwait];
void [withThenable, genericFunction, unconstrainedGeneric, parens, awaitParens, logical, emptyReturn];
void [inSwitch, inTry, inTryAwait, inCatch, inCatchAwait, inCatchWithFinally, inFinally];
void [inFinallyAwait, nested2, blockInTry, arrowInTry, ternary, ternaryInTry];
void [ternaryNotPromise, nestedTernary, arrow, arrowNo, arrowNotPromise, arrowConditional];
void [noAsync, noAsyncReturn, nestedNotAsync, SomeClass, objectValue, generator];
