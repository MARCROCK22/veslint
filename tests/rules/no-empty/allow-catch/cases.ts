declare function f(): void;

// Not reported with allowEmptyCatch.
try {
  f();
} catch (e) {}
try {
  f();
} catch {}

// Reported anyway.
try {
} catch (e) {
} finally {
}
