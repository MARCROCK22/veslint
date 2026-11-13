// Not reported: module code is strict, and block-level functions are allowed there.
if (Math.random()) {
  function inBlock() {}
  inBlock();
}
function outer() {
  function inner() {}
  return inner;
}
export function exported() {}
class C {
  static {
    function inStatic() {}
    inStatic();
  }
}
namespace N {
  function inNamespace() {}
  inNamespace();
}
// Variables are only checked with "both".
if (Math.random()) {
  var v = 1;
}
export { outer, C, v };
