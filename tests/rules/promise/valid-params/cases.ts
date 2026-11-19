// promise/valid-params: the number of arguments of the methods of promises.
declare const promise: Promise<number>;
declare const values: Promise<number>[];

Promise.resolve();
Promise.resolve(1);
Promise.resolve(1, 2);
Promise.reject(new Error('x'), 2);
Promise.all();
Promise.all(values, values);
Promise.allSettled(values);
Promise.any();
Promise.race(values, 1);
promise.then();
promise.then(() => 1);
promise.then(() => 1, () => 2);
promise.then(() => 1, () => 2, () => 3);
promise.catch();
promise.catch(() => 1, () => 2);
promise.finally();
promise.finally(() => 1);
promise.then(() => 1).catch().finally(() => 1, 2);
Promise.withResolvers(1);
