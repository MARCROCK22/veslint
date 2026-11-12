// In a script (no import or export), `await` can be a declared function, and outside an async
// function `await (n)` is a call that returns a floating promise.
declare function await(n: number): Promise<number>;
function f() {
  await (1);
  await (2).then(() => {});
}
async function g() {
  await (3);
}
void [f, g];
// More calls or accesses after it belong to the same expression.
function chains() {
  await (4).then(() => {}).finally(() => {});
  await (5).catch(() => {});
  await (6).then(() => {}, () => {});
  (await (7)).then(() => {});
  void await (8).then(() => {});
  [await (9)];
}
async function asyncChains() {
  await (10).toFixed();
  [await (11)];
}
void [chains, asyncChains];
