declare function lazy(callback: () => unknown): unknown;
declare function computedValue(callback: () => unknown): unknown;
declare function eager(callback: () => unknown): unknown;
class IgnoreCallbacks {
  a = lazy(() => this.c);
  b = eager(() => this.d);
  c = 1;
  d = 2;
  e = computedValue(() => this.f);
  f = (() => this.g)();
  g = 3;
}
