function g() {
  'use\x20strict';
  leak = 1;
  [arrayLeak, { objectLeak = 2 }] = [1, {}];
  defined = 3;
}
function h() {
  "other";
  'use strict';
  strictInside = 1;
  const inner = () => {
    arrowLeak = 1;
  };
  return inner;
}
const arrow = () => sloppyArrow = 1;
leak = 2;
for (forOfLeak of []) {
}
namespace N {
  inNamespace = 1;
}
enum E {
  A = 1,
}
type T<X> = X extends string ? { [K in keyof X]: X[K] } : (y: X) => void;
var defined;
/* global configured */
configured = 1;
