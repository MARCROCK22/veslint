// An `await using` declaration counts as an await of its function; a `using` one does not.
declare const res: AsyncDisposable;
declare const sync: Disposable;
async function withAwaitUsing() {
  await using a = res;
  return 1;
}
async function withUsing() {
  using a = sync;
  return 1;
}
async function forAwaitUsing() {
  for (await using a of [res]) {
  }
}
async function forUsing() {
  for (using a of [sync]) {
  }
}
async function inANestedFunction() {
  const inner = async () => {
    await using a = res;
  };
  return inner;
}
const arrow = async () => {
  await using a = res;
};
export { withAwaitUsing, withUsing, forAwaitUsing, forUsing, inANestedFunction, arrow };
// Comments between the keywords.
async function commented() {
  await /* c */ using a = res;
}
async function commentedHeader() {
  for /* h */ (/* i */ await /* j */ using a of [res]) {
  }
}
export { commented, commentedHeader };
