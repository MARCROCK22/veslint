// Reported.
const a = Symbol();
const b = Symbol?.();

// Not reported.
const c = Symbol('a');
const d = Symbol.for('a');
function shadow(Symbol: any) {
  return Symbol();
}
