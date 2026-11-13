declare const a: boolean;
declare function f(): void;

// Reported.
A: f();
B: while (a) {
  break;
}
C: D: for (;;) {
  break D;
}
E: /* comment */ {
  f();
}
F: {
  G: {
    break F;
  }
}
function g() {
  H: 'not a directive';
  I: `also`;
}
J: 'directive-like';

// Not reported.
K: for (;;) {
  continue K;
}
L: {
  break L;
}
