export {};
declare const s: string;
declare const n: number;
declare const b: boolean;
declare const big: bigint;
declare const u: undefined;
declare const nul: null;
declare const a: any;
declare const unk: unknown;
declare const nev: never;
declare const sym: symbol;
declare const obj: { x: number };
declare const arr: string[];
declare const nums: number[];
declare const objs: { x: number }[];
declare const tup: [string, number];
declare const empty: [];
declare const ro: readonly string[];
declare const re: RegExp;
declare const err: Error;
declare const typeErr: TypeError;
declare const url: URL;
declare const params: URLSearchParams;
declare const fn: () => void;
declare const lit: 'a' | 'b';
declare const mixed: string | number;
declare const maybe: string | undefined;
declare const mixedObj: string | { x: number };
declare const branded: string & { __brand: 'x' };
declare const both: { a: 1 } & { b: 2 };
declare const tpl: `x${string}`;
declare const upper: Uppercase<string>;
declare const date: Date;
declare const map: Map<string, number>;
declare const promise: Promise<string>;
enum E { A, B }
enum S { A = 'a', B = 'b' }
declare const e: E;
declare const es: S;
class MyError extends Error {}
class SubError extends MyError {}
declare const myErr: MyError;
declare const subErr: SubError;
interface MyURL extends URL {}
declare const myUrl: MyURL;
type Alias = { x: 1 };
declare const alias: Alias;
type Error2 = Error | URL;
declare const errOrUrl: Error2;
declare function tag(strings: TemplateStringsArray, ...values: unknown[]): string;

export const basics = `${s} ${n} ${b} ${big} ${u} ${nul} ${a} ${unk} ${nev} ${sym}`;
export const objects = `${obj} ${fn} ${date} ${map} ${promise} ${alias} ${both}`;
export const lists = `${arr} ${nums} ${objs} ${tup} ${empty} ${ro}`;
export const specials = `${re} ${err} ${typeErr} ${url} ${params} ${myErr} ${subErr} ${myUrl} ${errOrUrl}`;
export const unions = `${lit} ${mixed} ${maybe} ${mixedObj} ${branded} ${tpl} ${upper} ${e} ${es}`;
export const literals = `${'x'} ${1} ${true} ${null} ${undefined} ${void 0} ${10n} ${/re/} ${[1, 2]} ${{}} ${[]}`;
export const expressions = `${(obj)} ${((obj))} ${obj, s} ${s, obj} ${obj as any} ${<any>obj} ${obj!} ${obj satisfies object}`;
export const functions = `${() => 1} ${function () {}} ${class {}} ${Symbol()} ${new Date()}`;
export const nestedOnes = `${`${obj}`} ${`a${s}`}`;
export const taggedOnes = tag`${obj} ${a}`;
export const optionals = `${obj?.x} ${arr?.[0]} ${maybe ?? obj}`;
export const multiline = `
  ${obj}
  ${
    obj
  }`;

export function genericFunction<T>(t: T): string {
  return `${t}`;
}
export function genericText<T extends string>(t: T): string {
  return `${t}`;
}
export function genericNumber<T extends number | boolean>(t: T): string {
  return `${t}`;
}
export function genericObject<T extends { x: number }>(t: T): string {
  return `${t}`;
}
export function genericError<T extends Error>(t: T): string {
  return `${t}`;
}
export class SomeClass {
  value = 1;
  someText(): string {
    return `${this} ${this.value}`;
  }
}
namespace local {
  export class Error {
    message = '';
  }
  export interface URL {
    href: string;
  }
}
declare const localErr: local.Error;
declare const localUrl: local.URL;
declare const errCode: Error & { code: number };
declare const strOrNum: string | number | bigint;
export const shadows = `${localErr} ${localUrl} ${errCode} ${strOrNum}`;
export function constrained<T extends string | Error, U extends T>(t: T, u: U): string {
  return `${t} ${u}`;
}
