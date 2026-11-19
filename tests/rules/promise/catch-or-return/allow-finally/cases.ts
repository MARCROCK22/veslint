// promise/catch-or-return with allowFinally.
declare const promise: Promise<number>;
declare function handle(error: unknown): void;

promise.then((x) => x).catch(handle).finally(() => {});
promise.then((x) => x).finally(() => {});
promise.catch(handle).finally(() => {}).finally(() => {});
