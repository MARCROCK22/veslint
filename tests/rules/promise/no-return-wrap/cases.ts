// promise/no-return-wrap: no Promise.resolve or Promise.reject returned from a promise callback.
declare const promise: Promise<number>;
declare function handle(value: unknown): void;

promise.then((x) => {
  return Promise.resolve(x);
});
promise.then((x) => Promise.resolve(x));
promise.catch((error) => {
  return Promise.reject(error);
});
promise.then(function (x) {
  if (x) {
    return Promise.reject(new Error('x'));
  }
  return Promise.resolve(1);
});
promise.then(function (this: unknown, x: number) {
  return Promise.resolve(x);
}.bind(null));
promise.then((x) => {
  return Promise.all([x]);
});
promise.then((x) => {
  handle(() => Promise.resolve(x));
});
function outside() {
  return Promise.resolve(1);
}
const arrow = () => Promise.resolve(2);
promise.then((x) => {
  return x;
});
export { arrow, outside };
