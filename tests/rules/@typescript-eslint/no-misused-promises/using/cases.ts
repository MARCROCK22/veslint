// typescript-eslint 8.72: a `using` declaration whose value's `[Symbol.dispose]` returns a
// thenable, and a variable whose type's dispose returns void given such a value.
declare const asyncDispose: { [Symbol.dispose](): Promise<void> };
declare const syncDispose: { [Symbol.dispose](): void };
function usingChecks() {
  using a = asyncDispose;
  using b = syncDispose;
  const c: Disposable = asyncDispose;
  const d: Disposable = syncDispose;
  const e = asyncDispose;
  void [a, b, c, d, e];
}
void usingChecks;
