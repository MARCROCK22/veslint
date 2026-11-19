// promise/spec-only: only the standard members of Promise.
declare const values: Promise<number>[];

Promise.resolve(1);
Promise.all(values);
Promise.withResolvers();
Promise.done();
Promise.map(values, (x) => x);
Promise['delay'](1);
Promise['race'](values);
Promise[`any`](values);
Promise[name](values);
Promise.prototype.then;
Promise.prototype.finally;
Promise.prototype.spread;
Promise.prototype['tap'];
Promise.prototype;
const name = 'all';
const { reject } = Promise;
export { reject };
