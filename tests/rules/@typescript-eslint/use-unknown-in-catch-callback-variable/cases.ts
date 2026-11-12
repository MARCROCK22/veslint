declare const promise: Promise<number>;
declare const thenable: PromiseLike<number>;
declare const notThenable: { catch(f: (e: any) => void): void; then: number };
declare const maybe: Promise<number> | undefined;
declare const cond: boolean;
declare const handler: ((e: any) => void) | undefined;
declare const none: [];

promise.catch(e => e);
promise.catch((e) => e);
promise.catch((e: any) => e);
promise.catch((e: unknown) => e);
promise.catch((e: Error) => e);
promise.catch(() => {});
promise.catch(function (e) {
  return e;
});
promise.catch(function* (e) {
  yield e;
});
promise.catch(async e => e);
promise.catch((e = 1) => e);
promise.catch(({ message }) => message);
promise.catch(([first]) => first);
promise.catch(({ message } = { message: '' }) => message);
promise.catch((...args) => args);
promise.catch((...args: unknown[]) => args);
promise.catch((...args: [unknown]) => args);
promise.catch((...args: [any]) => args);
promise.catch((...args: any[]) => args);
promise.catch((e: unknown, extra?: number) => [e, extra]);
promise.catch((e?: unknown) => e);
promise.catch((e?) => e);

promise.then(v => v, e => e);
promise.then(v => v);
promise.then(v => v, (e: unknown) => e);
promise.then(undefined, e => e);
promise.then(...none, (e: any) => e);
promise.then(v => v, ...[(e: any) => e]);
promise.catch(...[(e: any) => e]);
promise.then(
  v => v,
  ({ message }) => message,
);
promise.then(v => v, ([first]) => first);

promise.catch(cond ? e => e : (e: unknown) => e);
promise.catch(handler || (e => e));
promise.catch(handler ?? ((e: unknown) => e));
promise.catch(cond && (e => e));
promise.catch((handler, e => e));
promise.catch((0, (e: unknown) => e));
promise.catch(cond ? (handler, e => e) : handler || (([a]) => a));
promise.catch(handler);
promise.catch((e => e) as never);
promise.catch((e => e)!);

promise['catch'](e => e);
promise[`catch`](e => e);
const method = 'catch';
promise[method](e => e);
promise['then'](v => v, e => e);
promise?.catch(e => e);
maybe?.catch(e => e);
(maybe?.catch)(e => e);
(promise.catch)(e => e);
promise.catch!(e => e);
thenable.then(v => v, e => e);
notThenable.catch(e => e);
Promise.resolve(1).catch(e => e);
Promise.reject().catch(e => {
  throw e;
});
promise.finally(() => {});
promise.catch(e => e, 5);

class Custom {
  catch(f: (e: any) => void): void {
    void f;
  }
  then(a: () => void, b: (e: any) => void): void {
    void [a, b];
  }
}
new Custom().catch(e => e);
new Custom().then(() => {}, e => e);
promise.catch(function (this: void, e) {
  return e;
});
promise.catch(function (this: void, e: unknown) {
  return e;
});
promise.catch(<T,>(e: T) => e);
async function nested() {
  await promise.catch(e => promise.catch((inner: unknown) => [e, inner]));
}
void nested;
