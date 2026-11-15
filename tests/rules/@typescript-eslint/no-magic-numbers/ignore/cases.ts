declare function f(...args: unknown[]): void;
// Not reported: ignored values.
f(0, 1, -1, 2.5, 10n, -5n, 7n, -0, 0n, -0n, +1);
type T = 1 | -1;
enum E {
  A = 1,
  B = -1,
}
class K {
  readonly r = 1;
}
// Reported.
f(2, -2.5, 10, 5n, -7n, -10n);
