// Sorted: nothing.
export { default as a1 } from './a1.json' with { mode: 'x', type: 'json' };
// Not sorted.
export { default as a2 } from './a2.json' with { type: 'json', mode: 'x', extra: 'y' };
// One attribute.
export { default as a3 } from './a3.json' with { type: 'json' };
// String keys.
export { default as a4 } from './a4.json' with { 'type': 'json', 'b-key': 'x', a: 'y' };
// export * is not checked; renamed exports are.
export * from './side.css' with { type: 'css', layer: 'base' };
export { b5 as b5x } from './b5.js' with { z: '1', y: '2' };
// On several lines, with comments.
export { default as a6 } from './a6.json' with {
  // the type
  type: 'json',
  /* the mode */
  mode: 'x', // after mode
  integrity: 'sha',
};
// eslint-disable-next-line.
export { default as a7 } from './a7.json' with {
  c: 'c',
  // eslint-disable-next-line perfectionist/sort-export-attributes
  a: 'a',
  b: 'b',
};
// Imports are not this rule's.
import { b5 } from './b5.js' with { z: '1', y: '2' };
// Case.
export { default as a8 } from './a8.json' with { b: '1', A: '2', a: '3' };
export { b5 };
