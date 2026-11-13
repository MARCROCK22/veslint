declare const a: boolean;

// Reported.
A: while (a) {
  break A;
}
B: for (;;) {
  continue B;
}
C: switch (1) {
  case 1:
    break C;
}
D: {
  break D;
}
E: if (a) {
  break E;
}
F: while (a) {
  G: while (a) {
    break F;
  }
}
H: for (const x of [1]) {
  function inner() {
    I: for (;;) {
      break I;
    }
  }
}

// Not reported.
while (a) {
  break;
}
for (;;) {
  continue;
}
