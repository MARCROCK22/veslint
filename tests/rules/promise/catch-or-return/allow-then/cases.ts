// promise/catch-or-return with allowThen.
declare const promise: Promise<number>;
declare function handle(error: unknown): void;

promise.then((x) => x, handle);
promise.then(null, handle);
promise.then((x) => x);
promise.then((x) => x, handle).finally(() => {});
