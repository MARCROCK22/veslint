// promise/no-callback-in-promise with timeoutsErr.
declare const promise: Promise<number>;
declare function cb(error: unknown, value?: number): void;
declare function other(value: unknown): void;

promise.then((x) => {
  setTimeout(() => cb(null, x));
});
promise.then((x) => other(x));
promise.then(() => other());
promise.then(() => setTimeout(cb));
other(promise);
