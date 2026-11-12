// prefer-reduce-type-parameter: an assertion on the initial value of Array#reduce.
declare const numbers: number[];
declare const words: readonly string[];
declare const tuple: [number, string];
declare const either: number[] | string[];
declare const both: number[] & { extra: true };
declare const arrays: number[][] & string[][];
declare const anything: any;
declare const notArray: { reduce(f: unknown, init: unknown): unknown };
declare const args: [(a: number[], b: number) => number[], number[]];

// Reported.
numbers.reduce((acc, n) => [...acc, n], [] as number[]);
numbers.reduce((acc, n) => [...acc, n], <number[]>[]);
numbers.reduce((acc, n) => acc.concat(n), ([] as number[]));
numbers['reduce']((acc, n) => ({ ...acc, [n]: n }), {} as Record<number, number>);
numbers[`reduce`]((acc, n) => acc + n, 0 as number);
numbers?.reduce((acc: string[], n) => [...acc, String(n)], [] as string[]);
(numbers.reduce)((acc, n) => [...acc, n], [] as number[]);
words.reduce((acc, w) => acc + w.length, 0 as number);
tuple.reduce((acc, item) => [...acc, String(item)], [] as string[]);
either.reduce((acc: number[], item: number | string) => acc, [] as number[]);
arrays.reduce((acc: number, item: number[]) => acc + item.length, 0 as number);
/* 😀 */ numbers.reduce((acc, n) => [...acc, n], [] as number[]);

// Reported: the method name is a constant (getStaticValue resolves it with the scope).
const reduceKey = 'reduce';
let reduceAlias = 'red' + 'uce';
numbers[reduceKey]((acc, n) => [...acc, n], [] as number[]);
numbers[reduceAlias]((acc, n) => [...acc, n], [] as number[]);

function generic<T extends number[]>(items: T): number[] {
  // Reported: the constraint of T is an array.
  return items.reduce((acc, n) => [...acc, n], [] as number[]);
}

// Not reported: the initial value is not assignable to the asserted type.
numbers.reduce((acc, n) => acc, {} as { total: number });
numbers.reduce((acc, n) => acc, [1] as unknown as string[]);

// Not reported: the method name is not a constant.
let changing = 'reduce';
changing = 'reduce';
numbers[changing as 'reduce']((acc, n) => [...acc, n], [] as number[]);

// Not reported: not an assertion, too few arguments, a spread, or not an array.
numbers.reduce((acc, n) => acc + n, 0);
numbers.reduce((acc, n) => acc + n);
numbers.reduce(...args);
numbers.reduce((acc, n) => acc + n, 0 satisfies number);
both.reduce((acc, n) => acc + n, 0 as number);
anything.reduce((acc: number, n: number) => acc + n, 0 as number);
notArray.reduce(() => 0, [] as number[]);
numbers.filter((n) => n > 0, [] as number[]);
void generic;
// The method name through a Map (a static value).
numbers[new Map([[1, 'reduce']]).get(1) as 'reduce']((acc, n) => acc.concat(n), [] as number[]);
