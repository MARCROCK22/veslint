declare const value: string;
declare const n: number;
declare function log(text: string): void;

// Sorted: nothing.
switch (value) {
  case 'a':
  case 'b':
    log('ab');
    break;
  case 'c':
    log('c');
    break;
  default:
    log('default');
}

// The tests of cases that fall through are sorted.
switch (value) {
  case 'c':
  case 'a':
  case 'b':
    log('abc');
    break;
  case 'e':
  case 'd':
    log('de');
}

// Blocks out of order.
export function blocks(): number {
  switch (value) {
    case 'z':
      return 1;
    case 'b':
      return 2;
    case 'a': {
      return 3;
    }
  }
  return 0;
}

// The default case last.
switch (value) {
  case 'b':
  default:
  case 'a':
    log('x');
    break;
  case 'c':
    log('c');
    break;
}

// The default block goes last.
switch (value) {
  default:
    log('default');
    break;
  case 'b':
    log('b');
    break;
  case 'a':
    log('a');
    break;
}

// A last block without break stays in place.
switch (value) {
  case 'c':
    log('c');
    break;
  case 'b':
    log('b');
    break;
  case 'a':
    log('a');
}

// Conditions: nothing.
switch (true) {
  case n > 1:
    break;
  case n < 0:
    break;
}
switch (value) {
  case 'b':
    break;
  case !value:
    break;
}

// Expressions as tests, on several lines.
declare const obj: { b: string; a: string };
switch (value) {
  case obj
    .b:
    log('b');
    break;
  case obj.a:
    log('a');
    break;
}

// Comments after the cases.
switch (value) {
  case 'b': // the b
  case 'a': // the a
    log('ab');
    break;
}
switch (value) {
  case 'b':
  default: // the default
  case 'a': // the a
    log('x');
    break;
}

// Nested switches.
switch (value) {
  case 'b':
    switch (n) {
      case 2:
        break;
      case 1:
        break;
    }
    break;
  case 'a':
    break;
}

// Numbers and template literals.
switch (n) {
  case 10:
  case 2:
  case 1:
    break;
}
switch (value) {
  case `b`:
  case `a`:
    break;
}

// Inline cases.
switch (value) { case 'b': log('b'); break; case 'a': log('a'); break }

// A block of cases that fall through moves whole: its cases stay together, and the blank lines
// between blocks stay where they were (veslint's fix; perfectionist's leaves a blank line inside
// the block, which no-fallthrough reports).
switch (value) {
  case 'y':
  case 'z': {
    log('yz');
    break;
  }

  case 'b': {
    log('b');
    break;
  }

  default:
    log('other');
}
