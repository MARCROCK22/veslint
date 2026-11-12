declare const anyValue: any;
declare const unknownValue: unknown;
declare const anyOrError: any | Error;
declare const unknownOrString: unknown | string;
function generic<T, U extends unknown, V extends any>(t: T, u: U, v: V) {
  Promise.reject(t);
  Promise.reject(u);
  Promise.reject(v);
}
void generic;
Promise.reject(anyValue);
Promise.reject(unknownValue);
Promise.reject(anyOrError);
Promise.reject(unknownOrString);
Promise.reject('text');
Promise.reject();
try {
  void 0;
} catch (caught) {
  Promise.reject(caught);
}
new Promise((resolve, reject) => {
  resolve(1);
  reject(anyValue);
  reject(unknownValue);
  reject(5);
});
