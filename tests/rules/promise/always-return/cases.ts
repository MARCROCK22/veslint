// promise/always-return: every `then()` callback returns or throws.
declare const promise: Promise<number>;
declare function use(value: unknown): void;
declare const process: { exit(code?: number): never; abort(): never };
declare let result: number;

promise.then((x) => {
  use(x);
});
promise.then(function (x) {
  if (x) {
    return x;
  }
});
promise.then((x) => {
  if (x) {
    use(x);
  } else {
    throw new Error('no x');
  }
}).catch(use);
promise.then((x) => {
  switch (x) {
    case 1:
      return 1;
    case 2:
      use(x);
      break;
    default:
      throw new Error('x');
  }
});
promise.then((x) => {
  try {
    return use(x);
  } catch {
    use(0);
  }
});
const chained = promise.then((x) => {
  use(x);
});
void promise.then((x) => {
  use(x);
});
await promise.then((x) => {
  use(x);
});
promise.then((x) => x * 2);
promise.then((x) => {
  return x;
});
promise.then(() => {
  process.exit(1);
});
promise.then(() => {
  process.abort();
});
promise.then(() => {
  throw new Error('x');
});
promise.then(use, (error) => {
  use(error);
});
promise.catch((error) => {
  use(error);
});
promise['then']((x) => {
  use(x);
});
promise.then((x) => {
  globalThis.result = x;
});
promise.then((x) => {
  result = x;
});
promise.then(async (x) => {
  await use(x);
});
promise.then(function* () {
  yield 1;
} as never);
export { chained };
