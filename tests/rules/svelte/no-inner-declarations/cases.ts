export function top() {}
if (top) {
  function inner() {}
  var v = 1;
  inner(v);
}
