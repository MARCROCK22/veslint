// `empty: "never"`, `"always"` for braces and tuples.
declare function log(...args: unknown[]): void;
export const array = [ ];
export const array2 = [];
export const object = {};
export const object2 = { };
export const object3 = {  };
const [ ] = [1];
const {} = { a: 1 };
type Tuple = [];
type Tuple2 = [ ];
type Literal = {};
interface Empty {}
enum EmptyEnum {}
export type { Tuple, Tuple2, Literal, Empty };
export { EmptyEnum };
export function declaration( ) {}
export const expression = function ( ) {};
export const arrow = ( ) => {};
declaration( );
log<string>( );
new Map( );
new Map<string, number>( );
type FunctionType = ( ) => void;
declare function declared( ): void;
export type { FunctionType };
export const method = { run( ) {}, get value( ) { return 1; } };
export class Klass { run( ) {} }
log( /* comment */ );
log(/* comment */);
export const commented = {/* comment */};
export const commented2 = { /* a */ /* b */ };
import {} from 'node:fs';
import { } from 'node:path';
import type { } from 'node:os';
import fs, { } from 'node:fs';
export { } from 'node:fs';
export {} from 'node:url';
export { };
export { fs };
if (array.length) log( );
export const nested = [{}, [ ], ( ) => {}];
