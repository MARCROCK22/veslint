// Cases of await-thenable (typescript-eslint 8.62.0, no options). The expected findings are in
// expected.txt, validated against typescript-eslint by tests/rules/reference.sh.
declare function task(): Promise<number>;
declare function syncFn(): number;
declare const anyValue: any;
declare const unknownValue: unknown;
declare const perhaps: Promise<number> | number;
declare const thenable: { then(cb: (v: number) => void): void };
declare const noThenable: { then: number };
declare const list: number[];
declare const promises: Promise<number>[];
declare const iterable: Iterable<number>;
declare const asyncIterable: AsyncIterable<number>;
const service = { save: async () => 1, count: () => 2 };

async function genericFunction<T, P extends Promise<number>, N extends number>(t: T, p: P, n: N) {
  await t;
  await p;
  await n;
}

async function cases() {
  await task();
  await syncFn();
  await 1;
  await 'someText';
  await anyValue;
  await unknownValue;
  await perhaps;
  await thenable;
  await noThenable;
  await service.save();
  await service.count();
  await (task());
  await Promise.all([task(), task()]);
  await Promise.all([task(), 1]);
  await Promise.allSettled([syncFn(), perhaps]);
  await Promise.all(list);
  await Promise.all(promises);
  for await (const n of list) {
    void n;
  }
  for await (const n of asyncIterable) {
    void n;
  }
  for await (const n of iterable) {
    void n;
  }
  return genericFunction;
}

// Calls whose type depends on overload or generic resolution.
declare function over(x: string): Promise<string>;
declare function over(x: number): number;
declare function ident<T>(x: T): T;
async function calls() {
  await over('a');
  await over(1);
  await ident(task());
  await ident(2);
  await (async () => 1)();
  await (() => 1)();
  await new Promise<number>(resolve => resolve(1));
  await Promise.resolve(1);
  await service?.save();
}

// Custom thenables and values that are not.
declare const withRest: { then(...cbs: Array<(v: number) => void>): void };
declare const optionalValue: { then?: (cb: () => void) => void };
declare const withoutCallback: { then(x: number): void };
declare const withoutParams: { then(): void };
declare const overloaded: { then(x: number): void; then(cb: () => void): void };
class MyPromise<T> extends Promise<T> {}
declare const mine: MyPromise<number>;
declare const nullValue: null;
async function thenables() {
  await withRest;
  await optionalValue;
  await withoutCallback;
  await withoutParams;
  await overloaded;
  await mine;
  await nullValue;
  await undefined;
  await void 0;
  await /* comment */ 1;
  await (1);
  await `template`;
  await (anyValue as number);
  await (unknownValue as Promise<number>);
  await await 1;
  const arrow = async () => await 1;
  return arrow;
}

// Aggregators: ways of reaching the method and of passing the values.
declare const tuple: [Promise<number>, number];
declare const goodTuple: [Promise<number>, Promise<string>];
declare const aSet: Set<Promise<number>>;
declare const numbers: Set<number>;
declare const blend: (Promise<number> | number)[];
const falseValue = { all: (x: number[]) => x };
async function aggregators() {
  await Promise.race([1]);
  await Promise.any(tuple);
  await Promise.all(goodTuple);
  await Promise.all(aSet);
  await Promise.all(numbers);
  await Promise.all(blend);
  await Promise.all(iterable);
  await Promise.all([...promises]);
  await Promise.all([...list]);
  await Promise.all([1, , task()]);
  await Promise['all']([2]);
  await Promise[`all`]([3]);
  await (Promise.all)([4]);
  await Promise?.all([5]);
  await MyPromise.all([6]);
  await Promise.all();
  await Promise.all([anyValue, unknownValue]);
  falseValue.all([7]);
}

// for await over other types.
declare function generator(): AsyncGenerator<number>;
declare const union: number[] | AsyncIterable<number>;
async function loops() {
  for await (const n of generator()) {
    void n;
  }
  for await (const n of union) {
    void n;
  }
  for await (const n of anyValue) {
    void n;
  }
  for await (const c of 'abc') {
    void c;
  }
  for (const n of list) {
    void n;
  }
}

void cases;
void calls;
void thenables;
void aggregators;
void loops;

// Review cases: parentheses around the argument and around the elements of an aggregator.
async function withParens() {
  await Promise.all(([1, 2]));
  await Promise.all([(1), (task()), 2]);
  await Promise.all((list));
}
void withParens;

// With the patched grammar, `await x as T` is `(await x) as T`, as in TypeScript.
async function withAs() {
  await 1 as number;
  await 2 satisfies number;
  await task() as unknown;
}
void withAs;
