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

// eslint-plugin-unicorn 79.0.0: parameters named after the receiver (pluralize's singular).
declare function fn(x: unknown, y?: unknown, z?: unknown): boolean;
declare const items: string[];
declare const ITEMS: string[];
declare const Users: string[];
declare const boxes: string[];
declare const wolves: string[];
declare const knives: string[];
declare const cities: string[];
declare const movies: string[];
declare const children: string[];
declare const people: string[];
declare const indices: string[];
declare const data: string[];
declare const analyses: string[];
declare const mice: string[];
declare const sheep: string[];
declare const news: string[];
declare const classes: string[];
declare const lets: string[];
declare const cafés: string[];
declare const $items: string[];
declare const statuses: string[];
declare const theses: string[];
declare const women: string[];
declare const geese: string[];
declare const vertices: string[];
declare const s: string[];
declare const elements: string[];
const p1 = items.map(fn);
const p2 = ITEMS.map(fn);
const p3 = Users.filter(fn);
const p4 = boxes.map(fn);
const p5 = wolves.map(fn);
const p6 = knives.map(fn);
const p7 = cities.map(fn);
const p8 = movies.map(fn);
const p9 = children.map(fn);
const p10 = people.map(fn);
const p11 = indices.map(fn);
const p12 = data.map(fn);
const p13 = analyses.map(fn);
const p14 = mice.map(fn);
const p15 = sheep.map(fn);
const p16 = news.map(fn);
const p17 = classes.map(fn);
const p18 = lets.map(fn);
const p19 = cafés.map(fn);
const p20 = $items.map(fn);
const p21 = statuses.map(fn);
const p22 = theses.map(fn);
const p23 = women.map(fn);
const p24 = geese.map(fn);
const p25 = vertices.map(fn);
const p26 = s.map(fn);
const p27 = elements.map(fn);
items.forEach(fn);
const p28 = items.reduce(fn);
const p29 = items.map(object.method);

// Names the callback refers to are not shadowed.
declare const element: { format(x: unknown): string };
declare const index: number;
declare const handlers: Array<(x: unknown) => string>;
const q1 = list.map(element.format);
const q2 = list.map(handlers[index]);
const q3 = items.map(element.format as (x: unknown) => string);
const q4 = list.reduce(element.format as (a: number, b: number) => number);
declare const item: (x: unknown) => boolean;
const q5 = items.map(item);

// The declared parameters set the shallowest suggestion.
const two = (a: number, b: number) => a + b;
function three(a: number, b: number, c: number[]) { return a + b + c.length; }
const rest = (...args: number[]) => args.length;
const methods = { two(a: number, b: number) { return a + b; }, one: (a: number) => a };
const r1 = list.map(two);
const r2 = list.map(three);
const r3 = list.map(rest);
const r4 = list.map(methods.two);
const r5 = list.map(methods.one);
const r6 = list.reduce(three);
list.forEach(two);

// Values that are not functions, also through `const`.
const notFunction = 1;
const alsoNotFunction = notFunction;
const z9 = list.map(notFunction as any);
const z10 = list.map(alsoNotFunction as any);
const z11 = list.map(undefined as any);
const z12 = list.map(`x` as any);

// Receivers that are known not to be arrays.
declare const map: Map<string, number>;
declare const set: Set<number>;
declare const mixed: Map<string, number> | number[];
declare const maybe: number[] | undefined;
class MyArray extends Array<number> {}
declare const mine: MyArray;
declare const typed: Uint8Array;
map.forEach(callback);
set.forEach(callback);
mixed.forEach(callback);
maybe?.forEach(callback);
mine.forEach(callback);
typed.forEach(callback);

// Parentheses of the replaced callback.
const t1 = list.map(callback as any);
const t2 = list.map(flag ? callback : two);
list.forEach(callback!);
list.forEach(<any>callback);
