// A `PromiseConstructor` the project declares itself (lib es5 has none): typescript-eslint's
// isPromiseConstructorLike asks for one from the default library, so `Promise.all` here is not an
// aggregator it checks.
interface PromiseConstructor {
  all<T>(values: readonly T[]): Promise<T[]>;
  race<T>(values: readonly T[]): Promise<T>;
}
declare var Promise: PromiseConstructor;
declare const anyValue: any;
async function aggregators() {
  await Promise.all([1, 2]);
  await Promise.race(['a']);
  await 1;
  return anyValue;
}
export { aggregators };
