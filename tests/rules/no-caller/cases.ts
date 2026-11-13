// Reported.
function f() {
  const a = arguments.callee;
  const b = (arguments as any).caller;
  return [a, b];
}

// Not reported.
function g() {
  return arguments.length;
}
const o = { callee: 1 };
const h = o.callee;
