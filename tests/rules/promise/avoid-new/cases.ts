// promise/avoid-new: no `new Promise(…)`.
declare function run(cb: () => void): void;
declare const Library: { Promise: PromiseConstructor };

const a = new Promise<void>((resolve) => run(resolve));
const b = new Promise(function (resolve, reject) {
  reject(new Error('x'));
});
const c = new (Promise)(() => {});
const d = new Promise;
const e = new Library.Promise(() => {});
const f = Promise.resolve(1);
const g = new PromiseLike();
class PromiseLike {}
export { a, b, c, d, e, f, g };
