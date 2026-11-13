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
D: for (const x of [1]) {
  if (a) break D;
}
E: do {
  break /* comment */ E;
} while (a);
F: while (a) {
  G: {
    break F;
  }
}

// Not reported.
H: while (a) {
  while (a) {
    break H;
  }
}
I: {
  break I;
}
J: while (a) {
  K: {
    break K;
  }
}
while (a) {
  break;
}
