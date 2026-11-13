declare const a: boolean;
declare function f(...args: unknown[]): void;

// Reported with "multi-or-nest".
if (a) {
  f();
}
if (a)
  f(1,
    2);
if (a)
  while (a) f();
while (a) { f(); }
for (;;) {
  // comment
}

// Not reported.
if (a) f();
if (a) {
  // comment
  f();
}
if (a) {
  f(1,
    2);
}
if (a)
  ;
