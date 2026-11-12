// return-await with 'always': outside an error-handling context the `await` is added by a fix.
declare function p(): Promise<number>;
declare const prom: Promise<number>;
declare const maybe: Promise<number> | undefined;
declare const cond: boolean;
async function a1() {
  return p();
}
async function a2() {
  return maybe ?? prom;
}
async function a3() {
  return cond ? prom : (maybe || p());
}
async function a4() {
  return (prom);
}
const a5 = async () => p();
const a6 = async () => (cond ? prom : maybe ?? p());
async function a7() {
  try {
    return p();
  } catch {
    return prom;
  }
}
