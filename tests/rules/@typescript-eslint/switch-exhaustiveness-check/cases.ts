export {};
type Day = 'mon' | 'tue' | 'wed';
declare const day: Day;
declare function work(): void;

switch (day) {
  case 'mon':
    break;
}
switch (day) {
  case 'mon':
  case 'tue':
  case 'wed':
    break;
}
switch (day) {
  case 'mon':
    break;
  default:
    break;
}
switch (day) {
  case 'mon':
  case 'tue':
  case 'wed':
    work();
    break;
  default:
    break;
}
switch (day) {
  case 'mon':
    break;
  // no default
}
switch (day) {
  case 'mon':
    work();
    /* NO DEFAULT */
}
switch (day) {
  case 'mon':
    break;
  // something else
}
switch (day) {
  case 'mon':
  case 'tue':
  case 'wed':
    break;
  // No Default
}
switch ((day)) {}

enum Color { Red, Green, Blue }
declare const color: Color;
switch (color) {
  case Color.Red:
    break;
}
enum Letter { A = 'a', B = 'b' }
declare const letter: Letter;
switch (letter) {
  case Letter.A:
}
namespace NS {
  export enum Inner { X, Y }
}
declare const inner: NS.Inner;
switch (inner) {
  case NS.Inner.X:
}

declare const flag: boolean;
switch (flag) {
  case true:
}
declare const maybe: Day | undefined;
switch (maybe) {
  case 'mon':
  case 'tue':
  case 'wed':
}
declare const opt: { v?: 'p' | 'q' };
switch (opt.v) {
  case 'p':
  case 'q':
}
switch (opt.v) {
  case undefined:
  case 'p':
}
declare const nullable: 'a' | null;
switch (nullable) {
  case 'a':
}
declare const num: number;
switch (num) {
  case 1:
}
declare const mixed: 'a' | number;
switch (mixed) {
  case 'a':
}
declare const big: 1n | 2n;
switch (big) {
  case 1n:
}
const sym1 = Symbol('a');
const sym2 = Symbol('b');
declare const syms: typeof sym1 | typeof sym2;
switch (syms) {
  case sym1:
}
declare const tagged: { kind: 'a' } | { kind: 'b' };
switch (tagged.kind) {
  case 'a':
}
export function generic<T extends 'x' | 'y'>(t: T): void {
  switch (t) {
    case 'x':
  }
}
const MON = 'mon';
switch (day) {
  case MON:
  case 'tue':
}
declare const branded: ('a' & { __brand: 1 }) | 'c';
switch (branded) {
  case 'c':
}
declare const anything: any;
switch (anything) {
  case 1:
}
declare const text: string;
switch (text) {
  case 'a':
    break;
  default:
}
switch (day) {
  case 'mon':
    break;
  default:
  case 'tue':
}
declare const maybeText: string | undefined;
switch (maybe) {
  case maybeText:
  case 'mon':
  case 'tue':
  case 'wed':
}
