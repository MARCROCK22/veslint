// promise/catch-or-return with allowThenStrict.
declare const promise: Promise<number>;
declare function handle(error: unknown): void;

promise.then((x) => x, handle);
promise.then(null, handle);
promise.then(undefined, handle);
