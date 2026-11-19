// promise/no-callback-in-promise: no callback called from inside a promise.
declare const promise: Promise<number>;
declare function cb(error: unknown, value?: number): void;
declare function callback(error: unknown, value?: number): void;
declare function done(): void;
declare function next(): void;
declare function other(value: unknown): void;
declare const process: { nextTick(fn: () => void): void };

promise.then((x) => cb(null, x));
promise.then(function (x) {
  callback(null, x);
});
promise.then(() => done()).catch((error) => next());
promise.then(cb);
promise.catch(next);
promise.then(done, callback);
promise.then((x) => other(x));
promise.then((x) => {
  setTimeout(() => cb(null, x));
});
promise.then(() => process.nextTick(() => done()));
promise.then(() => requestAnimationFrame(() => next()));
promise.then(() => setImmediate(cb));
cb(null);
setTimeout(() => cb(null));
function plain() {
  done();
}
promise.then((x) => {
  function inner() {
    cb(null, x);
  }
  inner();
});
export { plain };
