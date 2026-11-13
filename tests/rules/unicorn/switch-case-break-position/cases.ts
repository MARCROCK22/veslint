// unicorn/switch-case-break-position: a `break`, `continue`, `return` or `throw` right after the
// block of a case clause goes inside it (the fix is only for `break` and `continue`).
declare let a: number;
declare function f(n: number): void;

function g() {
  for (;;) {
    switch (a) {
      case 1: {
        f(1);
      }
      break;
      case 2: {
        f(2);
        // the last comment of the block
      }
      continue;
      case 3: {
        f(3);
      }
      return;
      case 4: {
        f(4);
      }
      throw new Error('4');
      // No fix: a comment between, a block on one line, a comment after on the same line.
      case 5: {
        f(5);
      }
      // between
      break;
      case 6: { f(6); }
      break;
      case 7: {
        f(7);
      }
      break; // after
      case 8: {
        f(8);
      }
      break
      // Not reported.
      case 9: {
      }
      break;
      case 10: {
        f(10);
        break;
      }
      case 11:
        f(11);
        break;
      case 12: {
        f(12);
      }
      f(12);
      break;
    }
  }
}
