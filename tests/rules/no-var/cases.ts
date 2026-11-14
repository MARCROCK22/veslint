// Reported and fixed to `let`.
var a = 1;
function f() {
  var b = 2;
  for (var i = 0; i < 3; i++) {}
  for (var k in {}) {
    console.log(k);
  }
  for (var m of [1]) {
    console.log(m);
  }
  return b + a;
}

// Reported without a fix.
function g(flag: boolean) {
  if (flag) var c = 1;
  switch (c) {
    case 1:
      var e = 1;
  }
  var x = x;
  console.log(y);
  var y = 1;
  var z = 1;
  var z = 2;
  var { p = p } = { p: 1 };
  var let2 = 1;
  {
    var inner = 1;
  }
  return [e, z, p, inner, let2];
}
for (var j = 0; j < 3; j++) {
  setTimeout(() => j);
}
while (a) {
  var uninit;
}
declare var w: number;
export var v = 1;
namespace N {
  var n = 1;
  export const m = n;
}

// Not reported.
declare global {
  var q: number;
}
let ok = 1;
const ok2 = ok;
export { f, g, ok2, N, w };

// Not fixed: a catch parameter of the name, or a hoisted function called before the declaration
// (10.15.0). The fix takes the whole declaration.
function catches() {
  try {} catch (e) { var e = 1; }
  try {} catch (e2) { { var e2 = 1; } }
  try {} catch (e3) { for (var e3 of []) {} }
  try {} catch ({ e4 }) { var e5 = e4; }
}
function hoisted() {
  early();
  var h = 1;
  var h2 = 2;
  function early() { return h; }
}
function hoistedLater() {
  var h3 = 1;
  later();
  function later() { return h3; }
}
function multi() {
  var m1 = 1, m2 = m1;
  for (var k in {}) {}
  for (var j = 0; j < 1; j++) {}
  return [m2, k, j];
}
declare var amb: number;
