// promise/prefer-await-to-then with strict.
declare const promise: Promise<number>;
declare function handle(value: unknown): void;

async function awaited() {
  await promise.then(handle);
}
class C {
  constructor() {
    promise.then(handle);
  }
}
promise.then(handle);
export { awaited, C };
