declare function ignored(value: unknown): unknown;
declare function used(value: unknown): unknown;
class OldDependencies {
  a = this.c ? this.b : 1;
  b = 1;
  c = 2;
  d = ignored(this.e);
  e = 3;
  f = used({ key: this.g });
  g = 4;
  h = () => this.i;
  i = 5;
  j = [this.k, new Set([this.l])];
  k = 6;
  l = 7;
  static m = OldDependencies.n;
  static n = 8;
  static {
    OldDependencies.o;
  }
  static o = 9;
}
