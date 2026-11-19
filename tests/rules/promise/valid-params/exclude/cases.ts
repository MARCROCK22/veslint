// promise/valid-params with exclude.
declare const promise: Promise<number>;

promise.catch(Error, () => 1);
Promise.resolve(1, 2);
Promise.reject(1, 2);
