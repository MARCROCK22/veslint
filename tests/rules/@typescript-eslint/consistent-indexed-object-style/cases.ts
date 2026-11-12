// consistent-indexed-object-style with 'record' (the default): an interface or a type literal with
// a single index signature, or a mapped type that does not use its key, is reported, with a fix or,
// when the fix would drop a comment, a suggestion.
type X = { value: string };
type Keys = 'a' | 'b';
declare class Base {}

interface A1 {
  [key: string]: number;
}
interface A2 {
  readonly [key: string]: number;
}
interface A3<T> {
  [key: string]: T;
}
interface A4<A = any, B extends string = 'x', in out C = never> {
  [key: A]: B | C;
}
export interface A5 {
  [key: number]: unknown;
}
export default interface A6 {
  [key: string]: unknown;
}
interface A7 extends Base {
  [index: number]: unknown;
}
declare interface A8 {
  [key: string]: X;
}
export declare interface A9 {
  [key: string]: X;
}
interface A10 {
  // a comment before the member
  [key: string]: X;
}
interface A11 {
  [key: /* key comment */ string]: X;
}
interface A12 {
  [key: string]: Map</* inside the value */ string, X>;
}
interface A13 {
  [key: (string)]: (X);
}
interface A14 {
  [key: string]: X;
  other: string;
}
interface A15 {
  other: string;
}
interface A16 {
  (): void;
}
interface A17 {
  [key: string]: X
}

// Circular, directly or through other types: not reported.
interface B1 {
  [key: string]: B1;
}
interface B2<T> {
  [key: string]: B2<T> | string;
}
interface B3 {
  [key: string]: B3 & {};
}
interface B4<T> {
  [key: string]: T extends B4<T> ? string : number;
}
interface B5 {
  [key: string]: B5[number];
}
interface B6 {
  [key: string]: {}[B6];
}
interface B7 {
  [key: string]: B8;
}
interface B8 {
  [key: string]: Record<string, B7>;
}
type B9 = boolean | B10;
interface B10 {
  [key: string]: B9;
}
type B11 = {
  [key: string]: B12;
};
type B12 = {
  [key: string]: { nested: B11 };
};

// Referencing the type without being circular for the rule: reported.
interface C1 {
  [key: string]: C1[];
}
interface C2 {
  [key: string]: { foo: C2 };
}
interface C3 {
  [key: string]: () => C3;
}
interface C4 {
  [key: string]: [C4];
}
interface C5 {
  [key: string]: A.C5;
}

// Type literals.
type D1 = { [key: string]: number };
type D2 = { readonly [key: string]: number };
type D3<T> = { [key: string]: T };
type D4 = Map<string, { [key: string]: number }>;
type D5 = { [key: string]: { [key: string]: D5 } };
type D6 = { [key: string]: string } | D6;
type D7 = { [key: string]: D7 };
type D8 = { [key: string]: X; };
type D9 = { [key: string]: X, };
type D10 = { /* comment */ [key: string]: X };
type D11 = { [key: string]: X /* comment */ };
let d12: { [key: string]: X } = {};
function d13(arg: { [key: string]: X }): { readonly [key: number]: X } {
  return arg;
}
type D14 = { [key: string]: X; other: number };
type D15 = {};
type D16<T extends { [key: string]: D16<{}> }> = T;
type D17 = [named: { [key: string]: D17 }];
type D18 = (arg: { [key: string]: D18 }) => { [key: string]: D18 };
type D19 = X extends { [key: string]: D19 } ? true : false;
class D20 {
  field: { [key: string]: X } = {};
}

// Mapped types.
type E1 = { [K in Keys]: X };
type E2 = { [K in Keys]?: X };
type E3 = { [K in Keys]+?: X };
type E4 = { [K in Keys]-?: X };
type E5 = { readonly [K in Keys]: X };
type E6 = { +readonly [K in Keys]: X };
type E7 = { -readonly [K in Keys]: X };
type E8 = { readonly [K in Keys]-?: X };
type E9 = { [K in Keys]: K };
type E10 = { [K in Keys as `get${K}`]: X };
type E11 = { [K in Keys as 'fixed']: X };
type E12<T> = { [K in keyof T]: X };
type E13<T> = { [K in (keyof T)]: X };
type E14 = { [K in Keys]: E14 };
type E15 = { [K in Keys]: E15 } | string;
type E16 = Map<string, { [K in Keys]: E16 }>;
type E17 = { [K in Keys]: { [J in Keys]: E17 } };
type E18 = { [K in /* comment */ Keys]: X };
type E19 = { [K in Keys]: (X) };
let e20: { [K in Keys]: X } = { a: { value: '' }, b: { value: '' } };
function e21(): { [k in keyof X]: unknown } {
  return { value: 1 };
}
type E22<K extends string = never> = { [k in K]: E22 };
type E23<K extends string = never> = { [k in K]: { foo: E24 } };
type E24 = E23;
type E25 = [named: { [K in Keys]: E25 }];

export type {
  A1, A2, A3, A4, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16, A17, B1, B2, B3, B4, B5, B6, B7,
  B8, B9, B10, B11, B12, C1, C2, C3, C4, C5, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, D11, D14,
  D15, D16, D17, D18, D19, E1, E2, E3, E4, E5, E6, E7, E8, E9, E10, E11, E12, E13, E14, E15, E16,
  E17, E18, E19, E22, E24, E25,
};
export { d12, d13, D20, e20, e21 };
