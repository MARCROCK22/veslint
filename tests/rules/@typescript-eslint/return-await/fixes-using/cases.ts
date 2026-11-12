// return-await: after a `using` declaration the context is an error-handling one, so the fix is
// a suggestion.
declare const p: Promise<number>;
declare const maybe: Promise<number> | undefined;
declare const sync: Disposable;
declare const res: AsyncDisposable;
async function usingBefore() {
  using a = sync;
  return p;
}
async function awaitUsingBefore() {
  await using a = res;
  return maybe ?? p;
}
async function usingAfter() {
  return await p;
  using a = sync;
}
