// checkThenables: true. A thenable counts when its `then` has a signature with two or more
// parameters whose first two are functions.
declare const p: Promise<number>;
declare const twoHandlers: { then(ok: () => void, fail: () => void): void };
declare const oneHandler: { then(ok: () => void): void };
declare const secondNotFunction: { then(ok: () => void, fail: number): void };
declare const overloaded: { then(ok: () => void): void; then(ok: () => void, fail: (e: unknown) => void, extra: number): void };
declare const unionThen: { then: ((ok: () => void) => void) | ((ok: () => void, fail: () => void) => void) };
declare const unionOfThenables: { then(ok: () => void, fail: () => void): void } | number;
declare const optionalHandlers: { then(ok?: () => void, fail?: (() => void) | null): void };
declare const restHandlers: { then(...handlers: (() => void)[]): void };
declare const thenProperty: { then: number };
declare const listOfThenables: { then(ok: () => void, fail: () => void): void }[];
declare class Custom<T> implements PromiseLike<T> {
  then<A, B>(ok?: ((value: T) => A | PromiseLike<A>) | null, fail?: ((reason: unknown) => B | PromiseLike<B>) | null): PromiseLike<A | B>;
}
declare const custom: Custom<number>;
async function f() {
  p;
  twoHandlers;
  oneHandler;
  secondNotFunction;
  overloaded;
  unionThen;
  unionOfThenables;
  optionalHandlers;
  restHandlers;
  thenProperty;
  listOfThenables;
  custom;
  custom.then(() => {});
  custom.then(() => {}, () => {});
  void custom;
}
export { f };
