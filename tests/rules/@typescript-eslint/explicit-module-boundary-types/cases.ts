// Reported: exported functions without types.
export function noTypes(a, b = 1, ...rest) {
  return a;
}
export function anyArgs(a: any, { b }: any, [c]: any, ...d: any[]): void {}
export function patterns({ a }, [b], ...[c]): void {}
export const arrow = (x) => x;
export const fnExpr = function (x: number) {
  return x;
};
export default function (y) {}
export class Klass {
  constructor(public p, private q, readonly r = 1) {}
  method(a) {}
  get getter() {
    return 1;
  }
  set setter(v) {}
  static s() {}
  private priv() {}
  #hash() {}
  protected prot() {}
  prop = () => 1;
  privateProp = function () {};
  accessor acc = () => 1;
  declare dec: () => void;
  ['comp' + 'uted']() {}
  [Symbol.iterator]() {}
}
export abstract class Abstract {
  abstract m(a);
  abstract set s(v);
  abstract get g();
}
export declare class Declared {
  m(a): void;
  n();
}
export const obj = {
  m(a) {},
  f: function (b: number) {},
  nested: { g: () => 1 },
};
export const arr = [() => 1, function () {}];
const later = () => 1;
let reassigned = () => 1;
reassigned = () => 2;
reassigned ||= () => 3;
export { later, reassigned };
function declaredAfterExport() {
  return () => 1;
}
export { declaredAfterExport };
export { usedBeforeDeclaration };
function usedBeforeDeclaration() {
  return () => 1;
}
class Local {
  method() {}
}
export { Local };
export namespace NS {
  export function inNamespace(a) {}
}
declare module 'mod' {
  export function inModule(a);
}
// Higher order functions.
export const higher = () => (x) => x;
export function higherDecl() {
  return function (y) {};
}
export const higherNested = () => () => () => {};
// Not reported: typed, local, private.
export function typed(a: number): void {}
export const typedArrow = (a: string): string => a;
type Fn = (a: number) => number;
export const typedVar: Fn = (a) => a;
export const asserted = ((a) => a) as Fn;
export const constAssert = () => ({ a: 1 }) as const;
function notExported(a) {}
const alsoNotExported = (a) => a;
export class Typed {
  constructor(a: number) {}
  set s(v: number) {}
  m(): void {}
}
export function overloaded(a: string): string;
export function overloaded(a: number): number;
export function overloaded(a: unknown) {
  return a;
}
export type { Fn };
export * from './other';
export { x } from './other';
