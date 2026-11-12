class Custom {}
class Derived extends Custom {}
class Other {}
type Alias = Custom;
declare const custom: Custom;
declare const derived: Derived;
declare const other: Other;
declare const alias: Alias;
declare const customOrOther: Custom | Other;
declare const customOrString: Custom | string;
declare const customAndMore: Custom & { more: number };
declare const response: Response;
declare const url: URL;
declare const date: Date;
Promise.reject(custom);
Promise.reject(derived);
Promise.reject(other);
Promise.reject(alias);
Promise.reject(customOrOther);
Promise.reject(customOrString);
Promise.reject(customAndMore);
Promise.reject('text');
Promise.reject(response);
Promise.reject(url);
Promise.reject(date);
new Promise((resolve, reject) => {
  resolve(1);
  reject(custom);
  reject(other);
  reject(response);
});
