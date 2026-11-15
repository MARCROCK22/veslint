// Sorted: nothing.
import a1 from './a1.json' with { mode: 'x', type: 'json' };
// Not sorted.
import a2 from './a2.json' with { type: 'json', mode: 'x', extra: 'y' };
// One attribute.
import a3 from './a3.json' with { type: 'json' };
// String keys.
import a4 from './a4.json' with { 'type': 'json', 'b-key': 'x', a: 'y' };
// Side-effect import and named imports.
import './side.css' with { type: 'css', layer: 'base' };
import { b5 } from './b5.js' with { z: '1', y: '2' };
// On several lines, with comments.
import a6 from './a6.json' with {
  // the type
  type: 'json',
  /* the mode */
  mode: 'x', // after mode
  integrity: 'sha',
};
// eslint-disable-next-line.
import a7 from './a7.json' with {
  c: 'c',
  // eslint-disable-next-line perfectionist/sort-import-attributes
  a: 'a',
  b: 'b',
};
// Exports are not this rule's.
export { b5 } from './b5.js' with { z: '1', y: '2' };
// Case.
import a8 from './a8.json' with { b: '1', A: '2', a: '3' };
export { a1, a2, a3, a4, a6, a7, a8 };
