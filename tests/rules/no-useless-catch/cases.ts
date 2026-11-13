declare function f(): void;
declare function g(): void;

// Reported.
try {
  f();
} catch (e) {
  throw e;
}
try {
  f();
} catch (e) {
  throw e;
} finally {
  g();
}
try {
  f();
} catch (e: unknown) {
  // comment
  throw (e);
}

// Not reported.
try {
  f();
} catch (e) {
  g();
  throw e;
}
try {
  f();
} catch (e) {
  throw new Error(String(e));
}
try {
  f();
} catch ({ message }) {
  throw message;
}
try {
  f();
} catch (e) {
  throw e2;
}
try {
  f();
} catch {
  throw new Error();
}
declare const e2: unknown;
