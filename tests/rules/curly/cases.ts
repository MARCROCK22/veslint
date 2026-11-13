declare const a: boolean;
declare const b: boolean;
declare function f(): void;

// Reported with "all".
if (a) f();
if (a) f();
else f();
if (a) f();
else if (b) f();
else { f(); }
while (a) f();
do f(); while (a);
for (;;) f();
for (const k in {}) f();
for (const v of []) f();
if (a)
  f();

// Not reported.
if (a) {
  f();
} else {
  f();
}
while (a) {}
if (a) f(); // after
