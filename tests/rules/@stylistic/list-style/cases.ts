// Spacing inside brackets on one line.
declare function log(...args: unknown[]): void;
declare const items: number[];
export const a = [ 1, 2 ];
export const b = {a: 1};
export const c = { a: 1 };
log( 1, 2 );
log(1, 2);
export const [ x, y ] = items;
export const { length } = items;
export const {length: size} = items;
export function f( p: number, q: number ): number { return p + q; }
export const g = ( p: number ) => p;
export const h = function ( p: number ) { return p; };
type Fn = ( p: number ) => void;
type Tuple = [ string, number ];
type Lit = {a: string; b: number};
interface Body {a: string}
enum E {A, B}
export type { Fn, Tuple, Lit, Body };
export { E };
export const generic = new Map< string, number >();
export function gen< T, U >(t: T, u: U): [T, U] { return [t, u]; }
if ( items.length ) log();
export const holes = [ , 1];
export const paren = [ (1), 2 ];
export const commented = [ /* first */ 1, 2 /* last */ ];
// Line breaks in lists on several lines.
export const d = [1,
  2];
export const e = [
  1, 2,
  3,
];
log(1,
  2);
log(
  1,
  2,
);
export function k(p: number,
  q: number): number { return p + q; }
interface Multi {
  a: string
  b: number
}
type Multi2 = { a: string;
  b: number };
export type { Multi, Multi2 };
export const single = [
  1
];
export const singleObject = {
  a: 1,
};
import { readFileSync,
  existsSync } from 'node:fs';
export { readFileSync, existsSync };
export const wrapped = [1, // comment
  2];
export const nested = [[1,
  2], 3];
log(() =>
  items.length);
log(items.map(item => {
  return item;
}));
export const typed = log< string >('x');
export const holes2 = [
  , 1,
  2];
// 6.0: the closing paren of a call whose last argument is parenthesized.
log(
  1,
  (2)
);
log(
  1,
  (2));
export const constructed = new Map<string, number>(
  (items.map(item => [String(item), item] as const))
);
// 6.0: the closing bracket of an array pattern with a type annotation.
export function pattern([
  first,
  second,
]: number[]): number { return first + second; }
export function pattern2([ first2, second2 ]: number[]): number { return first2 + second2; }
// Empty lists are ignored by default.
log( );
export const emptyArray = [ ];
export const emptyObject = {};
export {};
