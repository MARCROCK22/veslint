// A `using` or `await using` declaration before the returned value, in its scope or one around
// it inside the function, makes the context an error-handling one.
declare const p: Promise<number>;
declare const sync: Disposable;
declare const res: AsyncDisposable;
async function usingBefore() {
  using a = sync;
  return p;
}
async function usingBeforeAwait() {
  using a = sync;
  return await p;
}
async function usingAfter(c: boolean) {
  if (c) {
    return p;
  }
  using a = sync;
  return await p;
}
async function awaitUsing() {
  await using a = res;
  return p;
}
async function outerBlock() {
  using a = sync;
  {
    return p;
  }
}
async function innerBlockOnly() {
  {
    using a = sync;
  }
  return await p;
}
async function forHeader() {
  for (using a of [sync]) {
    return p;
  }
  return await p;
}
async function forInit() {
  for (using a = sync; ; ) {
    return p;
  }
}
async function nestedFunction() {
  using a = sync;
  const inner = async () => p;
  return await inner();
}
async function awaitedOutside() {
  using a = sync;
  return (await p) ? p : await p;
}
const arrow = async () => {
  using a = sync;
  return p;
};
export { usingBefore, usingBeforeAwait, usingAfter, awaitUsing, outerBlock, innerBlockOnly, forHeader, forInit, nestedFunction, awaitedOutside, arrow };
async function commented() {
  /* a */ using /* b */ a = sync;
  return p;
}
async function commentedHeader() {
  for (/* a */ using /* b */ a of [sync]) {
    return p;
  }
}
export { commented, commentedHeader };
