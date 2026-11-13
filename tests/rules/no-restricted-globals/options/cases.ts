declare function fdescribe(name: string, fn: () => void): void;
declare const myGlobal: { name: string };
// Reported.
const handler = () => event;
fdescribe('suite', () => {});
const p: Promise<number> = Promise.resolve(1);
window.event;
globalThis.Promise;
window['Promise'];
self.window.event;
myGlobal.name;
// Not reported.
function local(event: unknown) {
  return event;
}
type T = typeof Promise;
class Q implements PromiseLike<number> {
  then() {
    return undefined as any;
  }
}
export { handler, p, local, Q };
export type { T };
