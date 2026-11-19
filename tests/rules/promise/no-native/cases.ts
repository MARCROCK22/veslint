// promise/no-native: Promise used without being defined (it is a global of the libs, without a
// definition).
declare function work(): void;

const a = new Promise<void>((resolve) => resolve());
const b = Promise.resolve(1);
type T = Promise<number>;
function f(): Promise<void> {
  return Promise.reject(new Error('x'));
}
const c: PromiseLike<number> = b;
const d = window.Promise;
work();
export { a, b, c, d, f };
export type { T };
