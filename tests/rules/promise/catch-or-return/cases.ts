// promise/catch-or-return: a promise statement ends with catch() or is returned.
declare const promise: Promise<number>;
declare function handle(error: unknown): void;
declare const cy: { get(selector: string): Promise<number> };

promise.then((x) => x);
promise.then((x) => x).finally(() => {});
promise.then((x) => x, handle);
promise.then(null, handle);
Promise.resolve(1);
Promise.all([promise]).then(() => {});
promise.then((x) => x).catch(handle);
promise.catch(handle);
promise['catch'](handle);
promise.then((x) => x).catch(handle).finally(() => {});
cy.get('.x').then(() => {});
promise?.then((x) => x);
function returned() {
  return promise.then((x) => x);
}
const kept = promise.then((x) => x);
Promise.withResolvers();
export { kept, returned };
