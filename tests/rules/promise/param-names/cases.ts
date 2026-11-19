// promise/param-names: the parameters of the executor of `new Promise` are resolve and reject.
declare function run(...args: unknown[]): void;

new Promise((resolve, reject) => run(resolve, reject));
new Promise((_resolve, _reject) => run(_resolve, _reject));
new Promise((resolve) => run(resolve));
new Promise(() => {});
new Promise((ok, fail) => run(ok, fail));
new Promise(function (yes: (value: unknown) => void, no: (reason: unknown) => void) {
  run(yes, no);
});
new Promise((reject, resolve) => run(reject, resolve));
new Promise((resolve, reject, extra) => run(resolve, reject, extra));
new Promise(({ resolve }, [reject]) => run(resolve, reject));
new Promise((resolve = run, reject?) => run(resolve, reject));
new Promise((...args) => run(args));
new Promise(run);
new Promise((done) => run(done), 1);
