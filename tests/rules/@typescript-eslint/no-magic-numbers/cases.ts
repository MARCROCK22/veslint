declare const a: number[];
declare let v: number;
declare function f(...args: unknown[]): void;
// Reported: noMagic.
f(42);
f(-1, +2, -0x1f, 1e3, .5, 0b11, 0o7, 1_000, 10n, -10n);
v = 3;
v += 4;
const sum = 1 + 2;
a[5];
a[-1];
const obj = { x: 5, y: [6] };
const nested = { a: { b: 7 } };
class K {
  p = 8;
  readonly r = 9;
  static s = -10;
  m(x = 11) {
    return x * 12;
  }
}
function g(x = 13): void {}
enum E {
  A = 14,
  B = -15,
}
type T1 = 16;
type T2 = 17 | -18;
type T3 = { a: 19 };
type T4 = [20];
let t5: 21;
type T6 = T3[22];
type T7 = (23 | 24) & 25;
type T8 = 1 | (26 | 27);
interface I {
  x: 28;
}
// Not reported.
const c1 = 100;
let c2 = 101;
var c3 = 102;
const c4 = { x: 103 };
v = 0 ? 1 : 0;
parseInt('10', 16);
Number.parseInt('10', 8);
f(parseInt('1', 2));
const o2 = { k: 104 };
const { d = 105 } = { d: undefined as number | undefined };
