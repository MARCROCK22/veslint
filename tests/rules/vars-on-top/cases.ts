'use strict';
import { readFileSync } from 'node:fs';
var top = 1;
export var exported = 2;
declare var declared: number;
let lexical = 3;
var afterLexical = 4;
console.log(top, lexical, readFileSync);
var notOnTop = 5;

function f() {
  var a = 1;
  const b = 2;
  var c = 3;
  if (a) {
    var d = 4;
  }
  for (var i = 0; i < 1; i++) {}
  for (var k in {}) {}
  return [b, c, d];
}

const g = () => {
  'use strict';
  var a = 1;
  console.log(a);
  var b = 2;
  return b;
};

class C {
  static {
    var s = 1;
    console.log(s);
    var t = 2;
  }
  m() {
    var x = 1;
    return x;
  }
}

namespace N {
  var n = 1;
}
namespace M {
  export var first = 1;
  export function g() {}
  export var second = 2;
}
export { f, g, C, N, M, notOnTop, afterLexical, declared };
