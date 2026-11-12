declare const anyValue: any;
declare const unknownValue: unknown;
declare const anyOrError: any | Error;
declare const promise: Promise<number>;
function work(): void {}
function f1() {
  throw anyValue;
}
function f2() {
  throw unknownValue;
}
function f3() {
  throw anyOrError;
}
function f4<T, U extends unknown>(t: T, u: U) {
  if (t) {
    throw t;
  }
  throw u;
}
function r1() {
  try {
    work();
  } catch (e) {
    throw e;
  }
}
function r2() {
  try {
    work();
  } catch (e) {
    const copy = e;
    throw copy;
  }
}
promise.catch(e => {
  throw e;
});
promise.catch(function (e) {
  throw e;
});
promise.catch((e, extra?: unknown) => {
  throw extra;
});
