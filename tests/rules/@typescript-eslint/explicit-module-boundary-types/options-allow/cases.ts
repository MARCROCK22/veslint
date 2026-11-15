// Not reported: allowed names, any arguments, overloads.
export function allowed(a) {}
export const anyArg = (a: any, ...b: any[]): void => {};
export class C {
  method(a) {}
  [1]() {}
  ['method']() {}
  over(): void;
  over(a: number): void;
  over(a?: number) {}
  [Symbol.iterator](): void;
  [Symbol.iterator]() {}
}
export const o = { method() {}, allowed: () => 1 };
export function overloaded(a: string): string;
export function overloaded(a: unknown) {
  return a;
}
function inner(): void;
function inner() {}
export { inner };
export default function (a: string): void;
export default function (a: unknown) {}
// Reported.
export function other(a) {}
export class D {
  [2]() {}
  [Symbol.asyncIterator](): void;
  [Symbol.iterator]() {}
  over(): void;
  other() {}
}
export const p = { allowed: () => 1, method: function () {} };
