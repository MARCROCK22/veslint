// unicorn/no-array-method-this-argument: the `this` argument of array methods.
declare const list: number[];
declare const context: object;
declare function callback(this: object, x: number): boolean;
declare function make(): object;

const t1 = list.map(x => x, context);
const t2 = list.filter(callback, context);
const t3 = list.every(x => x > 0, make());
const t4 = list.some((callback), context,);
const t5 = Array.from(list, x => x, context);
const t6 = Array.from(list, callback, context);
const t7 = list.find(function (x) { return x > 0; }, context);
const t8 = list.forEach(new Function() as any, context);

// Not reported.
const z1 = list.map(x => x);
const z2 = list.map(undefined, context);
const z3 = list.map([] as any, context);
declare const _: { map(a: unknown, b: unknown, c: unknown): unknown };
const z4 = _.map(list, callback, context);
const z5 = Array.from(list, undefined, context);
