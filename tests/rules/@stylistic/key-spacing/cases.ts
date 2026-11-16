declare const c: string, d: string, j: number, k: object, m: number;

export const a1 = { a:1, b : 2, c  :  3, [c]:4 };
export const a2 = {
  a :1,
  bb:   2,
  [c]:3,
  [ d ] :  4,
  "e": 5,
  'f-g' :6,
  7:7,
  1e3 :8,
  0x10:  9,
  get h() { return 1 },
  set h(v) {},
  i() {},
  async l() {},
  j,
  ...k,
  m :m,
};
export const { a: x1, b :x2, c:  x3 = 1, ...rest } = a2;
export const a3 = { a /* c */ : 1, b: /* c */ 2, c:/* c */3, d /* c */: 4 };
export const a4 = { a:
  1, b
  : 2 };
export const a5 = { "é" :1, "🌷":2, [`t`] :3, "a\u00e9":4 };
export const a6 = { a:	1, b:  2, c: 3 };

export const group = {
  a: 1,
  bbb:   2,
  "cc" :3,

  dddd: 4,
  // a comment
  e:    5,
  /* first */
  /* second */
  ff:  6,

  // detached

  g: 7, hh:   8,
  [c]: 9,
  get x() { return 1 },
  ...k,
  "🌷": 10,
  "🇮🇳": 11,
  "o͂":   12,
  long_key_here: {
    inner: 1,
    in2:   2,
  },
};

export const multilineValues = {
  a: function () {
    return 1;
  },
  bb: [
    1,
  ],
  ccc: 3,
};

interface I1 { a:string; b :number; c  :  boolean; [k:string]:unknown; d?:string; readonly e :number }
type T1 = { a:string; b : number };
export class C1 { a:string = ''; b :number = 1; static c  : number; [k:string]:unknown; d!:string; #e :number = 1; declare f:number; g() {} }
export abstract class C2 { abstract g:number; h ?: string; }

interface Aligned {
  a: string;
  bbb:   number;
  cc : boolean;

  dddd: number;
  // comment
  e:    string;
  readonly [key: string]: unknown;
  f?:  string;
  g(): void;
  h:
    string;
  "🌷": number;
  i: { x: 1 }; j: 2;
  k: number;
}

type AlignedType = {
  a: string,
  bbbbbb:  number,
  [k: number] :  string,
}

export class AlignedClass {
  a: string = '';
  bbb:   number = 1;
  static cc : boolean;
  private dd: number;
  method(): void {}
  e:  string;
}

declare const inline: { a:string, b :number };
export function f(p: { a:string; bb :number }): void {}
export type Mapped = { [K in 'a']:string };

import json from './data.json' with { type :'json' };
export * from './mod' with { type:  'json' };
export { x } from './mod' with { type : "json" };
import json2 from './data2.json' with {
  type: 'json',
  other  :  'x',
};
export { json, json2 };

export const nbsp = { a:  1, b : 2 };
interface Odd {
  a
    : string;
  bb /* é */ : number;
  ccc: /* é */  boolean;
  "é":  number;
  [k: string /* x */]  : unknown;
}
export const oddKeys = {
  "é" /* ü */  : 1,
  [`a${c}`]:2,
};
// 6.0.0: a parenthesized type is aligned from its `(`
interface Ksp6A {
  b: 7;
  aaa: (123);
}
interface Ksp6B {
  aaa: 7;
  b: (123);
}
interface Ksp6C {
  aaa:   ((string | number));
  b: (() => void);
  cc:  /* c */ (boolean);
}
type Ksp6D = {
  x: (1);
  longer: 2;
};
export type { Ksp6A, Ksp6B, Ksp6C, Ksp6D };
