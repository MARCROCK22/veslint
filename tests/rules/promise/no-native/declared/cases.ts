// promise/no-native: a Promise of the module is no global.
declare const Bluebird: PromiseConstructor;

const Promise = Bluebird;
const a = Promise.resolve(1);
const b = new Promise(() => {});
export { a, b };
