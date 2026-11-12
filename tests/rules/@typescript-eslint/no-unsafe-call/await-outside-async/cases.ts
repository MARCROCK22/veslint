// Outside an async function, TypeScript reads `await` as an identifier when it is followed by `(`,
// `[` or a template: `await (x)` is a call and `` await `…` `` a tagged template. The code does
// not compile, but typescript-eslint reports those calls.
export {};
declare const x: unknown;
function f() {
  await (x);
  await (x, x);
  await `a${x}`;
  await `abc`;
  await x;
  await [x];
  return await `b${x}`;
}
async function g() {
  await (x);
  await `c${x}`;
}
void [f, g];
// More calls or accesses after it belong to the same expression: `await (x)(y)` calls what
// `await(x)` returns.
declare const anyValue: any;
function chains() {
  await (x)(x);
  await (x)(x)(x);
  await (x).y();
  await (x).y.z();
  await [x]();
  await [x].y();
  await `t`();
  await `t${x}`.y();
  await (x)`t`;
  await (anyValue)(x);
  await (anyValue()).y();
  new (await (x))();
  await -anyValue();
  return await (x)[0]();
}
async function asyncChains() {
  await (anyValue)(x);
  await (anyValue).y();
  await [anyValue]();
}
const arrow = () => await (x)(x);
class WithField {
  field = await (x)(x);
}
void [chains, asyncChains, arrow, WithField];
