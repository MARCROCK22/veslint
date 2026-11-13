declare const a: boolean;

// Not reported with allowLoop and allowSwitch.
A: while (a) {
  break A;
}
B: do {
  continue B;
} while (a);
C: switch (1) {
  case 1:
    break C;
}
D: for (const k in {}) {
  break D;
}

// Reported anyway.
E: {
  break E;
}
F: if (a) {
}
