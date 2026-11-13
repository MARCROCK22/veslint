// A module: every 'use strict' is unnecessary (fixed).
'use strict';
'use strict';

function f() {
  'use strict';
  return 1;
}

const g = (a = 1) => {
  'use strict';
  return a;
};

class C {
  m() {
    'use strict';
  }
}

function h() {
  "use strict";
  ('use strict');
  'other';
  'use strict';
}
export { f, g, C, h };
