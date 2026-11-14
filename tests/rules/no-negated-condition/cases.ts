declare const a: boolean, b: number, c: unknown;
declare function f(): void;

// Reported.
if (!a) { f(); } else { f(); }
if (b != 1) { f(); } else { f(); }
if (b !== 1) f(); else f();
const r1 = !a ? 1 : 2;
const r2 = b !== 1 ? 1 : 2;
const r3 = (!a) ? 1 : 2;
const r4 = ((b != 2)) ? 1 : 2;
if (!a) {
  f();
} else if (a) {
  f();
} else {
  f();
}
if (a) {} else if (!a) {} else {}

// Not reported.
if (!a) { f(); }
if (!a) { f(); } else if (b) { f(); }
if (a) { f(); } else { f(); }
if (b == 1) { f(); } else { f(); }
const k1 = a ? 1 : 2;
const k2 = !a && b ? 1 : 2;
const k3 = !(a as boolean) ? 1 : 2;
const k4 = (!a as boolean) ? 1 : 2;
const k5 = !c! ? 1 : 2;
export { r1, r2, r3, r4, k1, k2, k3, k4, k5 };
