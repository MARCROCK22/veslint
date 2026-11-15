declare const a: number[];
// Not reported.
enum E {
  A = 1,
  B = -2,
  C = +3,
}
type T1 = 4;
type T2 = 5 | -6;
type T3 = 1 | (2 | 3);
type T4 = { x: 1 }[7];
type T5 = [1, 2][0 | 1];
type T6 = T5[(8 | 9) & 10];
class K {
  readonly r = 11;
  private readonly s = -12;
  static readonly t = +13;
}
a[0];
a[1.0];
a[0x10];
a[-0];
a[0n];
a[4294967294];
// Reported.
let t7: 14;
type T8 = { x: 15 };
type T9 = Array<16>;
class L {
  p = 17;
}
a[-1];
a[1.5];
a[4294967295];
a[-1n];
a[4294967295n];
a[1e21];
