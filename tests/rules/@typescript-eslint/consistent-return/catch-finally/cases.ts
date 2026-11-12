// The first node that may throw in a `catch` block with a `finally` makes a path to the `finally`
// block (ESLint's makeFirstThrowablePathInTryOrCatchBlock), which an outer `catch` then catches.
declare function bar(): void;
declare const o: { x(): void };
export function throughOuterCatch() {
  try {
    try {
      o.x();
      return 1;
    } catch {
      bar();
      return 2;
    } finally {
      void 0;
    }
  } catch {
    void 0;
  }
}
export function withoutFinally() {
  try {
    try {
      o.x();
      return 1;
    } catch {
      bar();
      return 2;
    }
  } catch {
    void 0;
  }
}
export function catchWithoutThrowable() {
  try {
    try {
      o.x();
      return 1;
    } catch {
      return 2;
    } finally {
      void 0;
    }
  } catch {
    void 0;
  }
}
