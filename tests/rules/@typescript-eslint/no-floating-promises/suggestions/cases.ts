declare const promise: Promise<number>;
declare function getPromise(): Promise<number>;
declare const obj: {
  p: Promise<number>;
  get(): Promise<number>;
  maybe?: { run(): Promise<number> };
};
declare const cond: boolean;
declare function tag(strings: TemplateStringsArray): Promise<number>;

async function main() {
  promise;
  getPromise();
  obj.p;
  obj.get();
  obj['p'];
  (promise);
  ((getPromise()));
  cond ? promise : getPromise();
  cond && promise;
  promise || getPromise();
  promise ?? getPromise();
  (cond ? promise : getPromise());
  promise as Promise<number>;
  promise!;
  <Promise<number>>promise;
  promise satisfies Promise<number>;
  tag`x`;
  obj.maybe?.run();
  obj.maybe?.run()!;
  (obj.maybe?.run());
  new Promise<number>(() => {});
  new Promise<number>(() => {}).then(() => {});
  getPromise().then(() => {});
  getPromise().then(() => {}, undefined);
  getPromise().catch(null);
  getPromise().finally(() => {});
  1, promise;
  promise, 1;
  (1, promise);
  /* leading */ promise /* trailing */;
  getPromise()
    .then(() => {})
    .finally(() => {});
  await promise;
  void promise;
  [promise];
  typeof promise;
  (async () => {
    await promise;
  })();
  (async function () {})();
  !cond ? getPromise() : promise;
  cond ? (promise) : (getPromise());
  getPromise() as unknown as Promise<void>;
}
const résumé = '🎉é'; promise;
void [main, résumé];
