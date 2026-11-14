// Reported.
const a = /\x1f/;
const b = /\u001F/u;
const c = new RegExp('\x0c');
const d = RegExp('\\x1f', 'g');
const e = /(?<a>\x00)\k<a>/;
// Not reported.
const f = /\t\n/;
const g = /\x20/;
const h = new RegExp('\\t');
export { a, b, c, d, e, f, g, h };

// Only the global RegExp (10.15.0).
function shadowRegExp(RegExp: any) {
  return [RegExp('\x1f'), new RegExp('\x1f')];
}
const global1 = RegExp('\x1f');
