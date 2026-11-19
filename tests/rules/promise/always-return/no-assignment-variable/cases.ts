// promise/always-return with an empty ignoreAssignmentVariable.
declare const promise: Promise<number>;

promise.then((x) => {
  globalThis.name = String(x);
});
