declare const a: boolean;
declare const b: boolean;
declare function f(): void;

// Reported with "multi" and "consistent".
if (a) {
  f();
} else f();
if (a) f();
else if (b) {
  f();
  f();
} else f();

// Not reported.
if (a) f();
else f();
if (a) {
  f();
  f();
} else {
  f();
}
