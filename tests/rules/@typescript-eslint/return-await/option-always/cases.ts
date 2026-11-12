// The same cases under each value of the option: in a try, in a catch with and without a finally,
// in a finally, and outside of any error handling.
declare const p: Promise<number>;
declare const n: number;
declare const maybe: Promise<number> | number;
async function outside() {
  return p;
}
async function outsideAwait() {
  return await p;
}
async function inTry() {
  try {
    return p;
  } catch {
    return await p;
  }
}
async function inTryAwait() {
  try {
    return await p;
  } catch {
    return p;
  }
}
async function catchWithFinally() {
  try {
    return n;
  } catch {
    return p;
  } finally {
    console.log(n);
  }
}
async function catchWithFinallyAwait() {
  try {
    return n;
  } catch {
    return await p;
  } finally {
    console.log(n);
  }
}
async function inFinally() {
  try {
    return n;
  } finally {
    return p;
  }
}
async function inFinallyAwait() {
  try {
    return n;
  } finally {
    return await p;
  }
}
async function nonPromise() {
  return await n;
}
async function mayBePromise() {
  return await maybe;
}
async function mayBePromiseBare() {
  return maybe;
}
const arrow = async () => p;
const arrowAwait = async () => await p;
const branches = async (c: boolean) => (c ? p : await p);
async function nestedTry() {
  try {
    try {
      return n;
    } catch {
      return p;
    }
  } catch {
    return n;
  }
}
export { outside, outsideAwait, inTry, inTryAwait, catchWithFinally, catchWithFinallyAwait, inFinally, inFinallyAwait, nonPromise, mayBePromise, mayBePromiseBare, arrow, arrowAwait, branches, nestedTry };
