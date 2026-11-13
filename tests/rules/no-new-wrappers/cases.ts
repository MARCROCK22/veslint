// Reported.
const a = new String('a');
const b = new Number(1);
const c = new Boolean(true);

// Not reported.
const d = String('a');
const e = new Object();
function shadow(String: any) {
  return new String('a');
}
