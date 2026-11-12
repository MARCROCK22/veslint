// Cases of require-await (typescript-eslint 8.62.0, no options). The expected findings are in
// expected.txt, validated against typescript-eslint by tests/rules/reference.sh.
declare function task(): Promise<number>;
declare function syncFn(): number;
declare const thenable: { then(cb: (v: number) => void): void };
declare const anyValue: any;
declare const asyncIterable: AsyncIterable<number>;
declare function dec(...args: unknown[]): any;

// Function declarations.
async function withoutAwait() { return 1; }
async function withAwait() { await task(); }
async function emptyFn() {}
async function onlyComment() { /* nothing */ }
async function returnsPromise() { return task(); }
async function returnsThenable() { return thenable; }
async function returnsAny() { return anyValue; }
async function withForAwait() { for await (const x of asyncIterable) { void x; } }
async function nested() { const f = async () => { await task(); }; return f; }
async function outer() { await task(); function internal() { return 1; } return internal; }
function noAsync() { return 1; }
async function withVoid() { void task(); }
async function emptyReturn() { return; }
async function mixedReturn(c: boolean) { if (c) { return 1; } return task(); }
async function computedKey() { class K { [await task()]() { return 1; } } return K; }
async function innerComputedKey() { return class { async [syncFn()]() { await task(); } }; }

// Arrow functions.
const arrowWithoutAwait = async () => 1;
const arrowPromise = async () => task();
const arrowAwait = async () => await task();
const arrowParens = async () => (task());
const arrowAwaitParens = async () => (await task());
const arrowBlock = async () => { syncFn(); };
const arrowReturn = async () => { return task(); };
const onlyParam = async (p: Promise<number>) => { void p; };
const unionParam = async (p: Promise<number> | number) => { void p; };
const paramWithoutParens = async (p: number) => { void p; };
const bareParam = async p => { void p; };
const annotated = async (): Promise<void> => { syncFn(); };
const withDefault = async (p = task()) => { void p; };
const withRest = async (...ps: Promise<number>[]) => { void ps; };
const destructured = async ({ a }: { a: Promise<number> }) => { void a; };
const genericFn = async <T,>(x: T) => { void x; };
const emptyArrow = async () => {};
const arrowThenable = async () => thenable;

// Generators.
async function* generator() { yield 1; }
async function* promiseGenerator() { yield task(); }
async function* delegatingGenerator() { yield* asyncIterable; }
async function* syncGenerator() { yield* [1, 2]; }
async function* emptyGenerator() {}
async function* generatorWithAwait() { await task(); yield 1; }
async function* unionGenerator(c: boolean) { yield* (c ? asyncIterable : [1]); }
async function* literalGenerator() { yield 'someText'; }
function* generatorNotAsync() { yield 1; }

// Classes.
class SomeClass {
  async method() { return 1; }
  static async staticOne() { return 1; }
  async #privateOne() { return 1; }
  @dec async decorated() { return 1; }
  field = async () => { syncFn(); };
  @dec decoratedField = async () => { syncFn(); };
  static staticField = async () => { syncFn(); };
  async ['with spaces']() { return 1; }
  async withAwait() { await task(); }
  async returns() { return task(); }
  async *generatorMethod() { yield 1; }
  usesPrivate() { return this.#privateOne(); }
}

// Objects.
const objectValue = {
  async method() { return 1; },
  property: async () => { syncFn(); },
  func: async function () { syncFn(); },
  async *gen() { yield 1; },
  'with quotes': async () => { syncFn(); },
  1: async () => { syncFn(); },
  [`template`]: async () => { syncFn(); },
  withAwait: async () => { await task(); },
};

// Other named contexts.
export default async function () { syncFn(); }
const assigned = async function () { syncFn(); };
const named = async function ownOne() { syncFn(); };
let reassigned: () => Promise<void>;
reassigned = async () => { syncFn(); };
function withCallback(cb = async () => { syncFn(); }) { return cb; }
const paren = (async () => { syncFn(); });
[1].map(async (x) => { void x; });

void [withoutAwait, withAwait, emptyFn, onlyComment, returnsPromise, returnsThenable, returnsAny];
void [withForAwait, nested, outer, noAsync, withVoid, emptyReturn, mixedReturn];
void [computedKey, innerComputedKey];
void [arrowWithoutAwait, arrowPromise, arrowAwait, arrowParens, arrowAwaitParens];
void [arrowBlock, arrowReturn, onlyParam, unionParam, paramWithoutParens];
void [bareParam, annotated, withDefault, withRest, destructured, genericFn, emptyArrow];
void [arrowThenable, generator, promiseGenerator, delegatingGenerator, syncGenerator];
void [emptyGenerator, generatorWithAwait, unionGenerator, literalGenerator, generatorNotAsync];
void [SomeClass, objectValue, assigned, named, reassigned, withCallback, paren];

// Review case: a computed key that is not static gives the method no name.
const dynamicKey = 'k';
class WithDynamicKey { async [dynamicKey]() { return 1; } }
void WithDynamicKey;
