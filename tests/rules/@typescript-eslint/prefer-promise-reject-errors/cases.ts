declare const anyValue: any;
declare const unknownValue: unknown;
declare const maybeError: Error | undefined;
declare const errors: Error[];
declare const strings: string[];
class CustomError extends Error {}
class DeepError extends CustomError {}
interface ErrorShape extends Error {
  code: number;
}
declare const shaped: ErrorShape;
declare const readonlyError: Readonly<Error>;
declare const nestedReadonly: Readonly<Readonly<CustomError>>;
declare const readonlyString: Readonly<string>;
type MyReadonly<T> = { readonly [K in keyof T]: T[K] };
declare const ownReadonly: MyReadonly<Error>;
declare const intersection: Error & { extra: number };
declare const errorUnion: CustomError | TypeError;

// Promise.reject
Promise.reject(new Error('x'));
Promise.reject(new CustomError());
Promise.reject(new DeepError());
Promise.reject(shaped);
Promise.reject(readonlyError);
Promise.reject(nestedReadonly);
Promise.reject(readonlyString);
Promise.reject(ownReadonly);
Promise.reject(intersection);
Promise.reject(errorUnion);
Promise.reject(maybeError);
Promise.reject('text');
Promise.reject(5);
Promise.reject();
Promise.reject(undefined);
Promise.reject(anyValue);
Promise.reject(unknownValue);
Promise.reject(...errors);
Promise.reject(...strings);
Promise.reject((new Error('x')));
Promise.reject(('text'));
Promise.reject<string>('typed');
Promise['reject']('computed');
Promise[`reject`]('template');
const name = 'reject';
Promise[name]('constant');
let mutable = 'reject';
Promise[mutable as 'reject']('not static');
Promise?.reject('optional');
(Promise?.reject)('parenthesized chain');
(Promise.reject)('parenthesized');
Promise.reject!('non-null callee');
Promise.resolve('fine');
void Promise.reject`tagged`;

// Promise-like receivers
class MyPromise<T> extends Promise<T> {}
MyPromise.reject('subclass');
MyPromise.reject(new Error('x'));
declare const promiseInstance: Promise<number> & { reject(reason: unknown): void };
promiseInstance.reject('instance');
declare const thenable: { reject(reason: unknown): void };
thenable.reject('not a promise');
declare const ctor: PromiseConstructor;
ctor.reject('constructor value');
declare const eitherCtor: PromiseConstructor | typeof MyPromise;
eitherCtor.reject('union of constructors');
function generic<P extends PromiseConstructor>(p: P) {
  return p.reject('constrained');
}
void generic;

// new Promise
new Promise((resolve, reject) => {
  resolve(1);
  reject('text');
  reject(new Error('x'));
  reject();
  reject?.('optional call');
  (reject)('parenthesized');
  reject.call(null, 'member');
  void reject`tagged`;
  const inner = () => reject(maybeError);
  inner();
  setTimeout(reject, 1);
});
new Promise(function (resolve, reject) {
  resolve(1);
  reject(5);
});
new Promise(function* (resolve: unknown, reject: (reason: unknown) => void) {
  reject('generator');
  yield resolve;
});
new Promise((_, no) => no('renamed'));
new Promise((resolve, reject = () => {}) => {
  resolve(1);
  reject('default value');
});
new Promise((resolve, ...rest) => {
  resolve(1);
  rest[0]('rest');
});
new Promise((resolve, { length }) => {
  resolve(length);
});
new Promise(((resolve, reject) => {
  resolve(1);
  reject('parenthesized executor');
}));
new MyPromise((resolve, reject) => {
  resolve(1);
  reject('subclass constructor');
});
new ctor((resolve, reject) => {
  resolve(1);
  reject('constructor value');
});
declare const executor: (resolve: (value: number) => void, reject: (reason: unknown) => void) => void;
new Promise(executor);
new Promise((resolve, reject) => {
  resolve(1);
  new Promise((resolve2, reject2) => {
    resolve2(1);
    reject('outer from inner');
    reject2('inner');
  });
});
new Promise<number>((resolve, reject?: (reason: unknown) => void) => {
  resolve(1);
  reject?.('optional parameter');
});
