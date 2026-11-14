// unicorn/no-array-callback-reference: a function passed directly to an iterator method.
declare const list: number[];
declare function callback(x: number): boolean;
declare function reducer(a: number, b: number): number;
declare const object: { method(x: number): boolean };
declare const flag: boolean;
declare function isNumber(x: unknown): x is number;
const isPositive = (x: number): x is 1 => x > 0;

const c1 = list.map(callback);
const c2 = list.filter(object.method);
const c3 = list.some(flag ? callback : object.method);
list.forEach(callback);
const c4 = list.reduce(reducer);
const c5 = list.reduce(reducer, 0);
const c6 = list.map((callback));
const c7 = list.every(flag ? callback : x => x > 0);
const c8 = list.map(isNumber);
async function* f() {
  list.map(yield);
  list.map(await callback);
}

// Not reported.
const z1 = list.map(x => callback(x));
const z2 = list.filter(Boolean);
const z3 = list.map(String);
const z4 = list.map(callback.bind(null));
declare const Promise2: unknown;
const z5 = Promise.all(list.map(callback as any));
const z6 = list.filter(isNumber);
const z7 = list.find(isPositive);
function g(check: (x: unknown) => x is number) {
  return list.every(check);
}
const z8 = list.map(callback, undefined);
