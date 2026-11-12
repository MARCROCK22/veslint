// return-await with 'never': in an error-handling context the removal of `await` is a suggestion.
declare function p(): Promise<number>;
declare const prom: Promise<number>;
declare const cond: boolean;
async function a1() {
  try {
    return await p();
  } catch {
    return await /* comment */ prom;
  } finally {
    void 0;
  }
}
async function a2() {
  try {
    return cond ? await p() : (await prom);
  } catch {
    return 0;
  }
}
async function a3() {
  return await p();
}
