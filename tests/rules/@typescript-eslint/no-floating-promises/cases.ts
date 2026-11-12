// Cases of no-floating-promises (typescript-eslint 8.62.0, default options). The expected
// findings are in expected.txt, validated against typescript-eslint by tests/rules/reference.sh.
declare function task(): Promise<number>;
declare function syncFn(): number;
declare function perhaps(): Promise<number> | undefined;
declare function handler(e: unknown): void;
declare function overload(a: string): Promise<void>;
declare function overload(a: number): void;
declare const notFunction: number;
declare const aPromise: Promise<string>;
declare const promises: Promise<number>[];
declare const cond: boolean;
interface MyPromise<T> extends Promise<T> {
  extra: 1;
}
declare function mine(): MyPromise<number>;
declare class SafePromise<T> extends Promise<T> {}
declare function safe(): SafePromise<number>;
const service = { save: async () => 1, count: () => 2 };

function genericFn<T extends Promise<number>>(t: T) {
  t;
}

async function cases() {
  task();
  service.save();
  service.count();
  syncFn();
  perhaps();
  mine();
  safe();
  aPromise;
  promises;
  [task(), syncFn()];
  new Promise<void>((r) => r());
  (async () => {})();
  task().then((n) => n);
  task().then((n) => n, handler);
  task().then((n) => n, notFunction);
  task().catch(handler);
  task().catch(notFunction);
  task().catch(console.error);
  task().finally(() => {});
  task().catch(handler).finally(() => {});
  cond ? task() : syncFn();
  cond && task();
  (task(), syncFn());
  await task();
  void task();
  const stored = task();
  let assigned: Promise<number>;
  assigned = task();
  overload('x'); // reported because the overload that returns a Promise is resolved
  return [stored, assigned, genericFn];
}

// Cases that failed when the port requested types by position (before M8).
declare function ident<T>(x: T): T;
declare const anyValue: any;
async function beforeLimits() {
  ident(task());
  ident(1);
  (() => task())();
  (() => 1)();
  anyValue as Promise<number>;
  (anyValue as Promise<number>).catch(handler);
  [...promises];
  [...[1, 2]];
  perhaps()!;
  task() satisfies Promise<number>;
  await [task()];
  await Promise.all([task()]);
  task()!.catch(handler);
  (task().catch)(handler);
  task()['catch'](handler);
  task()[`then`](() => 1, handler);
  task().then(...[handler]);
  task().then(() => 1, ...[handler]);
  task().catch(...[handler]);
  cond ? task().catch(handler) : task();
  cond ?? task();
  syncFn() || task();
  task().catch(cond ? handler : notFunction);
  overload(1);
}
void beforeLimits;

// Review cases: private names, optional chains inside branches and a grammar ambiguity
// (`{ cb: … }` is a labeled block for TypeScript and an object for tree-sitter).
declare const optionalValue: { f(): Promise<number> } | undefined;
class WithPrivates {
  #catch(x: unknown) { return Promise.resolve(x); }
  #then(a: unknown, b: unknown) { return Promise.resolve([a, b]); }
  #finally(x: unknown) { return Promise.resolve(x); }
  use() {
    this.#catch(1);
    this.#then(1, 2);
    this.#finally(1);
  }
}
function stringCases() {
  optionalValue?.f().catch(handler);
  cond ? optionalValue?.f().catch(handler) : null;
  cond && optionalValue?.f().catch(handler);
  (optionalValue?.f())?.finally(() => {});
  optionalValue?.f().finally(() => {});
}
function tagFn() {
  { cb: task() }
}
void [WithPrivates, stringCases, tagFn];

// The body of an arrow that starts with `{` is a block: `cb:` is a label.
const arrowWithLabel = () => { cb: task() };
void arrowWithLabel;
