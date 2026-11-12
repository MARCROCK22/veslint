// In a script (no import or export), `await` can be a declared function. Outside an async function
// `await (x)` is a call and `` await `x` `` a tagged template, both of type void here, while
// `await [x]` is an element access.
declare function await(value: unknown): void;
declare namespace await {
  const [first]: [() => void];
}
function f() {
  const a = await (1);
  const b = await `text`;
  const c = await [0];
  return await (2);
}
async function g() {
  const d = await (3);
}
void [f, g];
// What follows belongs to the same expression: `await (4).x` reads a property of what the call
// returns.
function chains() {
  const e = await (4)(5);
  const f = [await (6), await [0]()];
  return await (7) ?? await [0]();
}
void chains;
