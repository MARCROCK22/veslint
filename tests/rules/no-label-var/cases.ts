declare let x: boolean;

// Reported.
let a = 0;
a: while (x) {
  break a;
}
function f(b: number) {
  b: for (;;) {
    break b;
  }
}

// Not reported.
c: while (x) {
  break c;
}
