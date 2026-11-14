// unicorn/no-useless-switch-case: empty cases right before a `default` at the end do what the
// `default` does; the suggestion removes each one.
declare let a: number;
declare function f(n: number): void;

switch (a) {
  case 1:
    f(1);
    break;
  case 2:
  case 3:
  default:
    f(0);
}
switch (a) {
  case 1: {}
  case 2: ;
  case 3: { ; {} }
  default:
    f(0);
}
switch (a) {
  case (a as number):
  default:
}
// Not reported.
switch (a) {
  case 1:
  case 2:
    f(2);
  default:
}
switch (a) {
  default:
  case 1:
}
switch (a) {
  case 1:
  case 2:
}

// 79.0.0: `case undefined`, `case void 0` and `case null` are kept in TypeScript; no suggestion
// for a test with a side effect or a case with a comment.
declare function g(): number;
switch (a) {
  case undefined:
  case void 0:
  case null:
  default:
}
switch (a) {
  case g():
  default:
}
switch (a) {
  case /* keep */ 1:
  default:
}
switch (a) {
  case 1: // keep
  default:
}
