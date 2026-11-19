// promise/no-nesting: no then() or catch() inside the callback of another.
declare const promise: Promise<number>;
declare function fetchMore(value: number): Promise<number>;
declare function handle(error: unknown): void;

promise.then((x) => fetchMore(x).then((y) => y));
promise.then((x) => {
  return fetchMore(1).then((y) => x + y);
});
promise.then((x) => {
  return fetchMore(1).then((y) => y);
});
promise.catch((error) => fetchMore(1).catch(handle));
promise.then(function (x) {
  const z = x + 1;
  return fetchMore(1).then(() => z);
});
promise.then((x) => {
  fetchMore(x).finally(() => {});
  return fetchMore(1).then(() => {
    return fetchMore(2).then(() => x);
  });
});
promise.then(() => {
  function inner() {
    return fetchMore(1).then(() => 1);
  }
  return inner();
});
promise.then(() => Promise.resolve(1).then(handle));
promise.then((x) => fetchMore(1).then(handle, () => x));
fetchMore(1).then((x) => x);
