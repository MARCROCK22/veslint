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

// 79.0.0: only simple `this` arguments are fixed; comments; receivers known not to be arrays.
declare const set: Set<number> & { map(cb: unknown, thisArg: unknown): void };
declare function getContext(): object;
const k1 = list.map(x => x, context);
const k2 = list.map(x => x, getContext());
const k3 = list.map(x => x, 'text');
const k4 = list.map(x => x, `text`);
const k5 = list.map(x => x, this);
const k6 = list.map(x => x, /* keep */ context);
const k7 = list.map(callback, getContext());
const k8 = list.map(callback, context /* keep */);
set.map(x => x, context);
const k9 = Array.from(list, x => x, context);
const k10 = Array.from(list, callback, context.toString);
