// `await using` needs a value with [Symbol.asyncDispose] in some part of its type.
declare const asyncRes: AsyncDisposable;
declare const syncRes: Disposable;
declare const both: AsyncDisposable & Disposable;
declare const either: AsyncDisposable | Disposable;
declare const anything: any;
declare const nothing: null;
declare function open(): Disposable;
async function f() {
  await using a = asyncRes;
  await using b = syncRes;
  await using c = both;
  await using d = either;
  await using e = anything;
  await using g = open(), h = asyncRes, i = (syncRes);
  await using j = nothing;
  using k = syncRes;
  for (await using l of [asyncRes]) {
  }
  for (using m of [syncRes]) {
  }
  await using n: Disposable = open();
}
export { f };
async function loops(sources: AsyncIterable<AsyncDisposable>, plain: AsyncDisposable[]) {
  for await (using a of sources) {
  }
  for await (await using b of sources) {
  }
  for await (using c of plain) {
  }
  for (await using d of plain) {
  }
}
export { loops };
