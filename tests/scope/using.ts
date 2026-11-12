// `using` and `await using` declarations.
declare const res: Disposable & AsyncDisposable;
{
  using a = res;
  a;
}
async function f() {
  await using b = res, c = b;
  for (using d of [res]) { d; }
  for (await using e of [res]) { e; }
  return c;
}
export { f };
