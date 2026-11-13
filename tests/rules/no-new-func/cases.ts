// Reported.
const a = new Function('a', 'b', 'return a + b');
const b = Function('a', 'return a');
const c = Function.call(null, 'a', 'return a');
const d = Function.apply(null, ['a', 'return a']);
const e = Function.bind(null, 'a', 'return a')();
const g = Function['call'](null, 'return 1');

// Not reported.
const h = Function.prototype;
const i = Function.toString();
function shadow(Function: any) {
  return new Function('x');
}
