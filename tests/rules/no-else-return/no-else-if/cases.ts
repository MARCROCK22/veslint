declare const a: boolean;
declare const b: boolean;
declare function f(): void;

// Reported with allowElseIf false.
function f1() {
  if (a) {
    return 1;
  } else if (b) {
    f();
  }
}
function f2() {
  if (a) {
    return 1;
  } else if (b) {
    return 2;
  } else {
    return 3;
  }
}

// Not reported.
function g1() {
  if (a) {
    f();
  } else if (b) {
    return 2;
  }
}
