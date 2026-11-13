'use strict';
function f(a = 1) {
  'use strict';
  leak = a;
}
class C {
  m() {
    inClass = 1;
  }
}
for (loopLeak in {}) {
}
