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

// No fix when the body would continue the statement before (10.15.0).
declare function g(): void;
declare let n: number;
function hazards() {
  g()
  L1: [1].forEach(g);
  g()
  L2: (n);
  g()
  L3: -n;
  g()
  L4: `x`;
  g();
  L5: [1].forEach(g);
  {
    L6: (n);
  }
  g()
  L7: n;
}
