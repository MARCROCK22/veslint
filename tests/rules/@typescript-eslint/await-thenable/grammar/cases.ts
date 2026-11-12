// Type arguments without a call after `await`: `await f<T>` awaits the instantiation expression
// `f<T>`, a function.
declare function make<T>(): T;
declare function makePromise<T>(): Promise<T>;
declare const holder: { get<T>(): Promise<T> };
async function instantiations() {
  const first = await make<Promise<number>>;
  const second = await holder.get<string>;
  await makePromise<number>;
  await make<number>
  await makePromise<number>()
  return [first, second];
}
export { instantiations };

// A comment with a line break ends the `return`, and the `await` is another statement.
async function afterReturn(n: number, p: Promise<number>) {
  if (n > 1) {
    return /* the result
    of the wait */ await n;
  }
  return /* one line */ await p;
}
export { afterReturn };
