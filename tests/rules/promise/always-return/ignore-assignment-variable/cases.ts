// promise/always-return with ignoreAssignmentVariable.
declare const promise: Promise<number>;
declare const state: { value: number; nested: { value: number } };
declare function use(value: unknown): void;

promise.then((x) => {
  window.name = String(x);
});
promise.then((x) => {
  state.nested.value = x;
});
promise.then((x) => {
  globalThis.name = String(x);
});
const kept = promise.then((x) => {
  state.value = x;
});
promise.then((x) => {
  use(x);
});
export { kept };
