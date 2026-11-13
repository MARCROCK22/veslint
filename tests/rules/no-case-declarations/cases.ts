declare const x: number;
declare function g(): void;

// Reported.
switch (x) {
  case 1:
    let a = 1;
    break;
  case 2:
    const b = 2;
    g();
  case 3:
    function f() {}
  case 4:
    class C {}
  default:
    let d = 1, e = 2;
}
switch (x) {
  case 1: // comment
    g();
    let a = 1; // trailing
}

// Not reported.
switch (x) {
  case 1: {
    let a = 1;
    break;
  }
  case 2:
    var b = 2;
  case 3:
    type T = number;
    interface I {}
    enum E {}
  case 4:
    g();
}
switch (x) {
  case 5:
    let last = 1; /* after */
}
