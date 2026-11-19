// promise/catch-or-return with terminationMethod (a text).
declare const promise: Promise<number> & { done(): void };
declare function handle(error: unknown): void;

promise.then((x) => x).done();
promise.then((x) => x).catch(handle);
promise['catch'](handle);
