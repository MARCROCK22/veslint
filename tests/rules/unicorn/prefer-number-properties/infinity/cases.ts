// unicorn/prefer-number-properties: `Number.parseInt` and the others instead of the globals.
// `isNaN` and `isFinite` get a suggestion (they convert their argument); `Infinity` is checked
// with checkInfinity and `NaN` unless checkNaN is false (both in infinity/).
const a1 = parseInt('10', 10);
const a2 = parseFloat('1.5');
const a3 = isNaN(1);
const a4 = isFinite(1);
const a5 = NaN;
const a6 = Infinity;
const a7 = -Infinity;
const a8 = globalThis.parseInt('1');
const a9 = { NaN };
function f() {
  return-Infinity;
}
const parse = parseInt;

// Not reported.
const z1 = Number.parseInt('1');
function shadowed(parseInt: (s: string) => number) {
  return parseInt('1');
}
