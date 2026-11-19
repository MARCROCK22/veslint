// promise/no-promise-in-callback: no promise inside a Node-style callback.
declare const promise: Promise<number>;
declare function read(path: string, cb: (err: Error | null, data?: string) => void): void;
declare function handle(value: unknown): void;

read('a', (err, data) => {
  promise.then(handle);
});
read('a', function (error) {
  Promise.resolve(error).catch(handle);
});
function onDone(err: Error | null) {
  promise.then(handle);
}
read('a', (err) => {
  return promise.then(handle);
});
read('a', (failure) => {
  promise.then(handle);
});
promise.then((err) => {
  promise.then(handle);
});
read('a', (err) => {
  const nested = () => promise.finally(handle);
  nested();
});
export { onDone };
