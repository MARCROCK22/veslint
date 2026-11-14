// checksConditionals.flagUnions (typescript-eslint 8.72): `all` reports a union with a thenable,
// `strict` only `Promise<T> | T` (and `none`, the default, only an always thenable value).
declare const promise: Promise<number>;
declare const promiseOrNumber: Promise<number> | number;
declare const promiseOrString: Promise<number> | string;
declare const promiseOrUndefined: Promise<number> | undefined;
declare const nested: Promise<number | string> | number | string;
declare const twoPromises: Promise<number> | Promise<string> | number | string;
if (promise) {}
if (promiseOrNumber) {}
if (promiseOrString) {}
if (promiseOrUndefined) {}
if (nested) {}
if (twoPromises) {}
const value = promiseOrNumber ? 1 : 2;
while (promiseOrNumber && value) {}
export { value };
