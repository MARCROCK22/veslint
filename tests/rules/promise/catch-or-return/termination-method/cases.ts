// promise/catch-or-return with terminationMethod (a list).
declare const promise: Promise<number> & { asCallback(cb: unknown): void; done(): void };
declare function handle(error: unknown): void;

promise.then((x) => x).asCallback(handle);
promise.then((x) => x).done();
promise.then((x) => x);
promise.catch(handle);
