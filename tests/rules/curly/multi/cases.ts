declare const a: boolean;
declare const b: boolean;
declare function f(): void;

// Reported with "multi".
if (a) {
  f();
}
while (a) { f(); }
do { f(); } while (a);
do{f();} while (a);
do{-1;} while (a);
for (;;) { f() }
if (a) { f() }
[1].map(f);
if (a) { f()
}
x++
if (a) { x++ }
f();
if (a) { const g = () => {} } [1];
if (a) { f(); } else { f(); }

// Not reported.
if (a) f();
if (a) {
  f();
  f();
}
if (a) {
  let x = 1;
}
if (a) {
  if (b) f();
} else f();
if (a) {}
declare let x: number;
if (a) { f(); } /* after */
