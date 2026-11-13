declare function work(n: number): void;
enum Kind {
  A,
  B,
  C,
}
// Reported.
function falls(kind: Kind): void {
  switch (kind) {
    case Kind.A:
      work(1);
    case Kind.B:
      work(2);
    default:
      work(3);
  }
}
function blockFalls(n: number): void {
  switch (n) {
    case 1: {
      work(1);
    }
    case 2:
      work(2);
  }
}
function emptyWithBlankLine(n: number): void {
  switch (n) {
    case 1:

    case 2:
      work(2);
      break;
  }
}
// Not reported.
function fine(kind: Kind): number {
  switch (kind) {
    case Kind.A:
      work(1);
      break;
    case Kind.B:
      return 2;
    case Kind.C:
      throw new Error('c');
    default:
      work(4);
  }
  return 0;
}
function commented(n: number): void {
  switch (n) {
    case 1:
      work(1);
    // falls through
    case 2:
      work(2);
    // fall through
    case 3: {
      work(3);
      /* falls through */
    }
    case 4:
      work(4);
  }
}
function empty(n: number): void {
  switch (n) {
    case 1:
    case 2:
      work(2);
  }
}
function nested(n: number): void {
  switch (n) {
    case 1:
      switch (n + 1) {
        case 2:
          work(2);
          break;
        default:
          break;
      }
      break;
    case 2:
      work(3);
  }
}
export { falls, blockFalls, emptyWithBlankLine, fine, commented, empty, nested };
