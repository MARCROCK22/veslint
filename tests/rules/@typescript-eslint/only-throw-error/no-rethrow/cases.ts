declare const promise: Promise<number>;
function work(): void {}
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
  } catch (e: any) {
    throw e;
  }
}
function r3() {
  try {
    work();
  } catch ({ message }) {
    throw message;
  }
}
promise.catch(e => {
  throw e;
});
promise.catch((e: string) => {
  throw e;
});
promise.catch((e: Error) => {
  throw e;
});
promise.then(undefined, (e: number) => {
  throw e;
});
