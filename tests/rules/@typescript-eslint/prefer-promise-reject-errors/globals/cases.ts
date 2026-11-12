// `/* global */` comments and lib names give ESLint variables without definitions.
/* global Promise, Error:off */
Promise.reject('text');
new Promise((resolve, reject) => reject('text'));
function shadowed(Promise: { reject(reason: unknown): void }) {
  Promise.reject('text');
}
export { shadowed };
