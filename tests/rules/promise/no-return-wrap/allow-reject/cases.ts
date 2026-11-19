// promise/no-return-wrap with allowReject.
declare const promise: Promise<number>;

promise.then((x) => {
  return Promise.reject(x);
});
promise.then((x) => Promise.resolve(x));
