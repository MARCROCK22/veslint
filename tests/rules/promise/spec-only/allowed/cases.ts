// promise/spec-only with allowedMethods.
declare const values: Promise<number>[];

Promise.map(values, (x) => x);
Promise.prototype.tap;
Promise['tap'];
Promise.each(values, () => {});
