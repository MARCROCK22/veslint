// typescript-eslint 8.72: an exported type alias or interface does not export the value of the
// same name, and a variable only used in types (not as a value) is used only as a type.
export type Merged = { a: number };
const Merged = 1;
export interface MergedInterface {
  a: number;
}
const MergedInterface = 2;
export type OnlyType = number;
export interface OnlyInterface {}
type Local = string;
const Local = 3;
export const usesLocal: Local = 'x';
const onlyAsType = { a: 1 };
export type FromValue = typeof onlyAsType;
const valueRead = 4;
export const readIt = valueRead;
export class MergedClass {}
export namespace MergedNamespace {
  export const x = 1;
}
export function f(a: number, b: number) {
  return b;
}
export function g(a: number, b: number): typeof b {
  return 1;
}
export function h(a: number, b: string): b is string {
  return true;
}
let typeOnlyLet = { a: 1 };
export type FromLet = typeof typeOnlyLet;
