declare function call(...args: unknown[]): void;
export const a = [1, 2,];
export const b = [1, 2];
export const c = [
  1,
  2,
];
export const d = [
  1,
  2
];
export const e = { x: 1, };
export const f = {
  x: 1
};
export const [g, h,] = [1, 2];
export const { length, } = [1];
export const { ...rest } = { r: 1 };
export const [...spread] = [1];
export function fn(p: number, q: number,): number { return p + q; }
export function fn2(
  p: number,
  ...others: number[]
): number { return p + others.length; }
export const arrow = (p: number,) => p;
export const expression = function (
  p: number
) { return p; };
call(1, 2,);
call(
  1,
  2
);
new Map([
  ['a', 1]
],);
import { readFileSync, } from 'node:fs';
import {
  existsSync
} from 'node:fs';
import def from 'node:path';
import * as os from 'node:os';
export { readFileSync, existsSync, def, os, };
export {
  fn as fn3
};
export const lazy = import('node:fs',);
export const lazy2 = import(
  'node:fs'
);
enum E { A, B, }
enum F {
  A,
  B
}
export { E, F };
type Generic<T, U,> = [T, U];
type Generic2<
  T
> = T;
type Tuple = [string, number,];
type Tuple2 = [
  string,
  number
];
type Fn = (p: number, q: number,) => void;
declare function declared(p: number,): void;
export type { Generic, Generic2, Tuple, Tuple2, Fn };
export const inst = new Map<string, number,>();
export const holes = [1, , ];
export const comment = [1, 2 /* last */];
export const commentAfter = [1, 2, /* last */];
export const multilineEnd = [
  1,
  2 // comment
];
export { declared };
