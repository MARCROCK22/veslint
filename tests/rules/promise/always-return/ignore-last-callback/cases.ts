// promise/always-return with ignoreLastCallback.
declare const promise: Promise<number>;
declare function use(value: unknown): void;

promise.then((x) => {
  use(x);
});
promise.then((x) => {
  use(x);
}).catch(use).finally(() => use(0));
const kept = promise.then((x) => {
  use(x);
});
promise.then((x) => {
  use(x);
}).then(use);
(promise.then((x) => {
  use(x);
}), 1);
(1, promise.then((x) => {
  use(x);
}));
promise?.then((x) => {
  use(x);
});
export { kept };
