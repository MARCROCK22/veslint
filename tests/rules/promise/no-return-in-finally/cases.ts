// promise/no-return-in-finally: no `return` in the callback of `finally()`.
declare const promise: Promise<number>;
declare function cleanup(): void;

promise.finally(() => {
  return 1;
});
promise.finally(function () {
  cleanup();
  return;
});
promise.then(() => 1).finally(() => {
  if (Math.random()) {
    return 2;
  }
  cleanup();
});
promise.finally(() => {
  cleanup();
});
promise.finally(() => cleanup());
promise.finally(cleanup);
promise.then(() => {
  return 3;
});
Promise.resolve(1).finally(async () => {
  return 4;
});
promise.finally(() => ({ body: [] }));
