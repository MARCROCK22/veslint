// unicorn/prefer-date-now: `Date.now()` instead of the time of a new Date.
declare let n: number;

const x1 = new Date().getTime();
const x2 = new Date().valueOf();
const x3 = new Date.getTime();
const x4 = Number(new Date());
const x5 = BigInt(new Date());
const x6 = +new Date();
const x7 = -new Date();
const x8 = new Date() - 1;
const x9 = 2 * new Date() / new Date();
n -= new Date();
n **= new Date();
function f1() {
  return+new Date();
}
function* f2() {
  yield+new Date;
}
// TypeScript: assertions around it are not looked through.
const x10 = (new Date() as Date).getTime();
const x11 = (new Date()).getTime();

// Not reported.
const z1 = new Date(0).getTime();
const z2 = new Date().getTime(1);
const z3 = new Date()?.getTime();
const z4 = new Date().getTime?.();
const z5 = new Date()['getTime']();
const z6 = Number(new Date(), 1);
const z7 = new Date() + 1;
n += new Date();
const z8 = String(new Date());
const z9 = Date.now();
