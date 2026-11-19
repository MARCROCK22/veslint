// promise/prefer-await-to-callbacks: no callbacks.
declare function read(path: string, cb: (err: Error | null) => void): void;
declare const emitter: { on(event: string, fn: (err: Error) => void): void; once(event: string, fn: (err: Error) => void): void };
declare const items: number[];
declare const _: { map(list: number[], fn: (err: number) => number): number[] };
declare function map(list: number[], fn: (err: number) => number): number[];

function withCallback(value: number, callback: (err: Error | null) => void) {
  callback(null);
}
const withCb = (cb: () => void) => cb();
read('a', (err) => {});
read('a', function (error) {});
read('a', (data) => {});
emitter.on('error', (err) => {});
emitter.once('error', (err) => {});
items.map((err) => err);
items.forEach((error) => error);
_.map(items, (err) => err);
map(items, (err) => err);
async function inside() {
  await read('a', (err) => {});
}
function* generator() {
  yield read('a', (err) => {});
}
class C {
  method(value: number, cb: () => void) {}
}
export { C, generator, inside, withCallback, withCb };
