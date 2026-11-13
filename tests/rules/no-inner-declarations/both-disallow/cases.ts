// Reported.
if (Math.random()) {
  function inBlock() {}
  inBlock();
  var inBlockVar = 1;
}
function outer() {
  while (Math.random()) {
    var x = 1;
    function loopFn() {}
    loopFn();
  }
  for (var i = 0; i < 1; i++) {}
  for (var k in {}) {}
  return x;
}
class C {
  static {
    if (Math.random()) {
      function deep() {}
      deep();
    }
  }
}
namespace N {
  function inNamespace() {}
  var nv = 1;
  inNamespace();
}

// Not reported.
function ok() {
  var a = 1;
  function nested() {}
  return [a, nested];
}
var top = 1;
export var exported = 2;
let lexical = 3;
if (Math.random()) {
  let scoped = 1;
  console.log(scoped);
}
export { outer, C, N, ok, top, lexical, inBlockVar };
