// Outside an async function, TypeScript reads `await [i]` as the element access `await[i]`.
// The code does not compile, but typescript-eslint reports those accesses.
export {};
declare const x: unknown;
declare const anyValue: any;
function f() {
  await [x];
  await [x, x];
  await [anyValue];
  await [(anyValue)];
  await ['literal'];
  await [x, anyValue];
  await (x);
  return await [x];
}
async function g() {
  await [anyValue];
  await [x, x];
}
void [f, g];
// An index across several lines: the message carries the line breaks, which veslint writes as `\n`.
function acrossLines() {
  return await [
    x,
    anyValue
  ];
}
void acrossLines;
// More calls or accesses after it belong to the same expression: `await (x).y` is `(await(x)).y`
// and `await [x].y` is `(await[x]).y`.
function chains() {
  await (anyValue).y;
  await (x).y;
  await (x).y.z;
  await (x)[anyValue];
  await (x)(anyValue).z;
  await [x].y;
  await [anyValue].y;
  await [x][anyValue];
  await [x, anyValue].y.z;
  await [x](anyValue).y;
  await `t`.y;
  await `t${anyValue}`[anyValue];
  await (anyValue.a).b;
  await (x)?.y;
  await (x)!.y;
  await -anyValue.y;
  await +anyValue[x];
  return await (x).y[anyValue];
}
async function asyncChains() {
  await (anyValue).y;
  await [anyValue].y;
  await (x as any)[anyValue];
  await -anyValue.y;
}
const arrow = () => await (x).y;
class WithField {
  field = await (x).y;
  static async method() {
    const inner = () => await (anyValue).y;
    class Inner { field = await [anyValue].y; }
    return [inner, Inner, await (anyValue).y];
  }
}
void [chains, asyncChains, arrow, WithField];
