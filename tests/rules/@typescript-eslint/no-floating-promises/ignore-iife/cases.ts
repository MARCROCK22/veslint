// ignoreIIFE: true. A statement that calls a function expression or an arrow is skipped, async
// or not; an optional call or any other callee is not.
declare const p: Promise<number>;
(async () => {
  await p;
})();
(async function () {
  await p;
})();
(async function named() {
  await p;
})();
(() => p)();
(function () {
  return p;
})();
(function* () {
  yield 1;
})();
(async () => p)?.();
((async () => p))();
(async () => p)().then(() => {});
const run = async () => p;
run();
(async () => p)``;
new (class {
  then() {}
})();
