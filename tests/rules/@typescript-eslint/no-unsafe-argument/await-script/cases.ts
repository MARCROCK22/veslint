// In a script (no import or export), `await` can be a declared function, and outside an async
// function `await (a)` and `` await `…` `` are calls to it.
declare function await(...n: number[]): Promise<number>;
declare const anyValue: any;
function f() {
  await (anyValue);
  await (1, anyValue);
  await `${anyValue}`;
}
async function g() {
  await (anyValue);
}
void [f, g];
// More calls or accesses after it belong to the same expression.
declare function takesNumber(n: number): (m: number) => number;
function chains() {
  await (1).then(takesNumber(anyValue));
  await (anyValue).then(takesNumber(anyValue));
  await (1, 2).catch(anyValue);
  await `${1}`.finally(anyValue);
  takesNumber(await (1).length);
  takesNumber(1)(await (anyValue).length);
}
async function asyncChains() {
  await (anyValue).then(takesNumber(anyValue));
  takesNumber(await (anyValue).length);
}
void [chains, asyncChains];
