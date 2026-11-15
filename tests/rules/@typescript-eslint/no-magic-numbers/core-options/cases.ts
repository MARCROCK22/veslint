// Not reported.
function g(x = 1, { y = -2 } = {}): void {}
class K {
  p = 3;
  static q = -4;
}
const [z = 5] = [] as number[];
// Reported.
function h(x = 6 + 1): void {}
class L {
  p = [7];
  readonly r = 8;
}
