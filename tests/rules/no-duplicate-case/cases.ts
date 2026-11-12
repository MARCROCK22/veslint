// no-duplicate-case: a case whose test has the same tokens as an earlier one in its switch.
declare const value: unknown;
declare const n: number;
declare function f(x: number): number;
const enum Kind { A, B }

switch (value) {
  case 1:
  case 2:
    break;
  case 1:
    break;
  case 'a':
  case "a":
    break;
  case (2):
    break;
  case f(1):
  case f(1 /* the same tokens */):
    break;
  case n + 1:
  case n+1:
  case 1 + n:
    break;
  default:
    break;
}

// Each switch on its own, nested ones too.
switch (n) {
  case Kind.A:
    switch (n) {
      case Kind.A:
        break;
    }
    break;
  case Kind.B:
  case Kind.A:
    break;
}

// TypeScript's expressions are compared by their tokens too.
switch (value) {
  case value as string:
  case value as string:
  case value as number:
  case value!:
  case value!:
    break;
}
