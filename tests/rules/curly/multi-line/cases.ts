declare const a: boolean;
declare function f(...args: unknown[]): void;

// Reported with "multi-line".
if (a)
  f();
while (a)
  f();
if (a) f(1,
  2);
if (a) f(); else
  f();

// Not reported.
if (a) f();
if (a) { f(); }
if (a) {
  f();
}
while (a) f();
