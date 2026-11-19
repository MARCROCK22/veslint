// promise/no-callback-in-promise with exceptions.
declare const promise: Promise<number>;
declare function cb(error: unknown, value?: number): void;
declare function done(): void;
declare function next(): void;

promise.then(() => next());
promise.then(done);
promise.then((x) => cb(null, x));
promise.catch(cb);
