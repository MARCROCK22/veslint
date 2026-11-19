// promise/prefer-await-to-then: await rather than then(), catch() and finally().
declare const promise: Promise<number>;
declare function handle(value: unknown): void;
declare const cy: { get(selector: string): Promise<number> };

promise.then(handle);
function inFunction() {
  promise.then(handle).catch(handle).finally(() => {});
}
async function awaited() {
  await promise.then(handle);
}
function* yielded() {
  yield promise.then(handle);
}
class C {
  constructor() {
    promise.then(handle);
  }
  method() {
    promise.catch(handle);
  }
}
const arrow = () => promise.finally(handle);
function cypress() {
  cy.get('.x').then(handle);
}
function computed() {
  promise['then'](handle);
}
export { arrow, awaited, C, computed, cypress, inFunction, yielded };
