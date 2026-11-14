declare const a: boolean, b: boolean, c: boolean;
declare function f(): void;
declare let x: number;

// Reported (and fixed).
if (a) { f(); } else { if (b) { f(); } }
if (a) { f(); } else { if (b) { f(); } else { f(); } }
if (a) {
  f();
} else {
  if (b) {
    f();
  } else if (c) {
    f();
  }
}
if (a) f(); else{ if (b) f(); }
if (a) { f(); } else {
  if (b) f();
}
f();
if (a) { f(); } else { if (b) x++
}
[1].map(f);
if (a) { f(); } else { if (b) f(); }
(f)();

// Reported, not fixed.
if (a) { f(); } else { /* c */ if (b) { f(); } }
if (a) { f(); } else { if (b) { f(); } // c
}
if (a) { f(); } else { if (b) f() }
(f)();
if (a) { f(); } else { if (b) x++ }
f();

// Not reported.
if (a) { f(); } else { if (b) { f(); } f(); }
if (a) { f(); } else if (b) { f(); }
if (a) { if (b) { f(); } }
if (a) { f(); } else { let y = 1; if (b) { f(); } }
while (a) { if (b) { f(); } }
export {};
