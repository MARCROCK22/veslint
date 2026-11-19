// promise/catch-or-return with an empty terminationMethod.
declare const promise: Promise<number>;
declare function handle(error: unknown): void;

promise.catch(handle);
promise['catch'](handle);
