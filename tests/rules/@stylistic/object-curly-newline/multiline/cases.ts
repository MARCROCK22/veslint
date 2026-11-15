// Default options: consistent line breaks.
export const a = { x: 1 };
export const b = {
  x: 1 };
export const c = { x: 1
};
export const d = {
  x: 1,
};
export const e = { // comment
  x: 1 };
export const f = { x: 1 /* trailing */
};
export const { g,
  h } = { g: 1, h: 2 };
export function fn({ p, q
}: { p: number; q: number }): number {
  return p + q;
}
import {
  readFileSync } from 'node:fs';
import type { Stats
} from 'node:fs';
import * as path from 'node:path';
import def from 'node:os';
export { readFileSync, path, def };
export {
  type Stats };
type T = {
  a: string; };
interface I { a: string;
}
enum E {
  A }
enum F { B }
export type { T, I };
export { E, F };
export const empty = {
};
export const nested = { inner: {
  deep: 1 } };
export const m1 = { x: 1,
  y: 2 };
export const m2 = { x: 1, y: {
  z: 2 } };
