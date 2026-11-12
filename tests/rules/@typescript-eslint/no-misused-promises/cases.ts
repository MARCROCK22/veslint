// Cases of no-misused-promises (typescript-eslint 8.62.0, default options: checksConditionals,
// checksSpreads and checksVoidReturn). The expected findings are in expected.txt, validated
// against typescript-eslint by tests/rules/reference.sh.
declare function task(): Promise<number>;
declare function syncFn(): number;
declare const aPromise: Promise<number>;
declare const perhaps: Promise<number> | undefined;
declare const thenable: { then(cb: () => void): void };
declare const anyValue: any;
declare const objectPromise: Promise<{ a: number }>;
declare function withCallback(cb: () => void): void;
declare function withPromiseCallback(cb: () => Promise<void>): void;
declare function withBoth(cb: (() => void) | (() => Promise<void>)): void;
declare function withRest(...cbs: Array<() => void>): void;
declare function withTuple(...args: [number, () => void]): void;
declare function overloadedFn(cb: () => void): void;
declare function overloadedFn(cb: () => Promise<void>, x: number): void;
declare function genericFn<T>(cb: () => T): T;
declare function dec(...args: unknown[]): any;
declare class Emitter { on(event: string, cb: () => void): void }
declare const emitter: Emitter;
declare const list: number[];
declare const tuple: [number, string];
declare const util: { verify: (x: number) => Promise<boolean> };

// checksConditionals
async function conditionals() {
  if (aPromise) {}
  if (perhaps) {}
  if (await aPromise) {}
  if (thenable) {}
  while (aPromise) { break; }
  do { break; } while (aPromise);
  for (; aPromise; ) { break; }
  const t = aPromise ? 1 : 2;
  if (aPromise && syncFn()) {}
  if (syncFn() || aPromise) {}
  const a = aPromise && 1;
  const b = 1 && aPromise;
  const c = aPromise ?? 1;
  if (aPromise ?? 1) {}
  if (!aPromise) {}
  const d = !aPromise;
  if ((aPromise)) {}
  if (anyValue) {}
  if (task) {}
  if (task()) {}
  const e = (aPromise && 1) || 2;
  return [t, a, b, c, d, e];
}

// Array predicates.
function predicates() {
  list.filter(async x => x > 1);
  list.some(async () => true);
  list.find(x => x > 1);
  list.map(async x => x);
  tuple.every(async () => true);
  list['filter'](async () => true);
  [...new Set<number>()].findIndex(async () => true);
  list.filter(util.verify);
}

// checksVoidReturn: arguments.
withCallback(async () => {});
withCallback(() => task());
withCallback(() => {});
withPromiseCallback(async () => {});
withBoth(async () => {});
withRest(() => {}, async () => {});
withTuple(1, async () => {});
emitter.on('x', async () => {});
new Promise<void>(async resolve => { resolve(); });
void task().finally(async () => {});
void task().then(async () => {});
list.forEach(async x => { void x; });
overloadedFn(async () => {});
genericFn(async () => 1);
[1].forEach(task);

// checksVoidReturn: variables.
const v1: () => void = async () => {};
const v2: () => Promise<void> = async () => {};
const v3 = async () => {};
let v4: () => void;
v4 = async () => {};
v4 = () => {};
const v5: { (): void } = async () => {};
const v6: number = 1;
type Callback = () => void;
const v7: Callback = async () => {};

// checksVoidReturn: properties.
interface Options { onRun: () => void; name: string; onFinish?: () => void }
const p1: Options = { onRun: async () => {}, name: 'x' };
const p2: Options = { onRun: async (): Promise<void> => {}, name: 'x' };
const p3: Options = { onRun: task, name: 'x' };
const p4: Options = { async onRun() {}, name: 'x' };
const p5: Options = { async onRun(): Promise<void> {}, name: 'x' };
const onRun = async () => {};
const p6: Options = { onRun, name: 'x' };
const p7: Options = { onRun: () => {}, name: 'x', onFinish: async () => {} };
const p8 = { onRun: async () => {} };

// checksVoidReturn: return values.
function returnsCallback(): () => void { return async () => {}; }
function returnsNumber(): number { return 1; }
function returnsPromiseCallback(): () => Promise<void> { return async () => {}; }
const arrowReturns = (): (() => void) => async () => {};

// checksVoidReturn: inherited methods.
interface WithMethod { method(): void }
class Implementing implements WithMethod { async method() {} }
class Base { method(): void {} }
class Child extends Base { async method() {} }
class StaticChild extends Base { static async method() {} }
interface Extending extends WithMethod { method(): Promise<void> }
class GenericClass<T> { method(): T { return undefined as T; } }
class GenericChild extends GenericClass<void> { async method() {} }
class Decorated extends Base { @dec async method() {} }
abstract class Abstract { abstract method(): void }
class Concrete extends Abstract { async method() {} }

// checksSpreads
const s1 = { ...aPromise };
const s2 = { ...perhaps };
const s3 = { ...{ a: 1 } };
const s4 = [...list];
const s5 = { ...anyValue };
async function spreadAwait() { return { ...(await objectPromise) }; }

void [conditionals, predicates, v1, v2, v3, v5, v6, v7, p1, p2, p3, p4, p5, p6, p7, p8];
void [returnsCallback, returnsNumber, returnsPromiseCallback, arrowReturns];
void [Implementing, Child, StaticChild, GenericChild, Decorated, Concrete, s1, s2, s3, s4, s5];
void spreadAwait;
export type { Extending };

// Review cases: accessors in object literals (they are not a MethodDeclaration) and `!`/`as` under
// logical operators, which the original tree-sitter grammar nests the other way around (fixed by
// the grammar patch in patches/).
const withAccessor: Options = { get onRun() { return () => {}; }, name: 'x' };
declare const perhapsPromise: Promise<number> | undefined;
declare const condition: boolean;
function badlyNested() {
  if (condition && perhapsPromise!) {}
  if (condition ?? perhapsPromise as Promise<number>) {}
}
void [withAccessor, badlyNested];
