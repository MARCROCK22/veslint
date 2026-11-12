// ImportVisitor, ExportVisitor, enums and namespaces.
import Default from 'm1';
import * as Namespace from 'm2';
import { named, renamed as local, type InlineType, default as viaDefault } from 'm3';
import type TypeDefault from 'm4';
import type { OnlyType } from 'm5';
import type * as TypeNs from 'm6';
import Mixed, { other } from 'm7';
import Req = require('m8');
import type TReq = require('m9');
import Alias1 = Namespace.a.b;
import 'side-effect';
import json from './data.json' with { type: 'json' };
export import Reexported = Namespace.c;
export * from 'm10';
export * as star from 'm11';
export { a as b, c } from 'm12';
export type { T1 } from 'm13';
export { type T2 } from 'm14';
const value1 = 1, value2 = 2;
type Type1 = number;
interface Both { x: number }
const Both = 1;
export { value1, value2 as renamedExport, Both };
export type { Type1, OnlyType as RenamedType };
export { type Type1 as T1b, named };
export const exported1 = Default, exported2 = local;
export function exportedFn(p: InlineType): TypeDefault { return p as any; }
export class ExportedClass extends Mixed {}
export enum ExportedEnum { A = 1 }
export namespace ExportedNs { export const inner = other; }
export type ExportedType = TypeNs.X | Req.Y | TReq | OnlyType;
export interface ExportedIface { v: typeof viaDefault }
export declare const declared1: number;
export declare function declaredFn(): void;
enum Plain { A, B = A + 1, C = B << 1, 'quoted' = 4, D = quoted, E = Plain.A, F = 'x'.length }
const enum Const { X = 1, Y = X }
declare enum Declared { P, Q = P }
enum Merge { M1 = 1 }
enum Merge { M2 = M1 }
namespace Outer {
  export const o1 = 1;
  const hidden = o1;
  export namespace Nested { export const n1 = hidden; }
  export function f() { return Nested.n1; }
  export type T = typeof o1;
  export enum InNs { Z = o1 }
}
namespace Dotted.Path.Deep { export const d = Outer.o1; }
namespace Merge2 { export const m = 1; }
namespace Merge2 { export const n = m; }
declare module 'ambient' { export const amb: number; export default amb; }
declare module 'wild*';
declare global { var globalVar: number; interface Window { added: string } function globalFn(): void; }
declare namespace DeclaredNs { const dn: number; }
globalVar; json; Alias1; Plain.A; Const.X; Declared.P; Dotted.Path.Deep.d; Merge2.n; DeclaredNs.dn; Namespace;
export default value1;
