const a1 = 1, b1 = 1, c1 = 1, a2 = 1, b2 = 1, c2 = 1, x3 = 1, a6 = 1, b6 = 1, z7 = 1, b7 = 1;
const a11 = 1, b11 = 1, d11 = 1, a12 = 1, b12 = 1, c12 = 1, a13 = 1, A13 = 1, b13 = 1, B13 = 1;
type T9 = 1;
type A9 = 1;
// Sorted: nothing.
export { a1, b1, c1 };
// Not sorted.
export { c2, a2, b2 };
// One specifier, and declarations.
export { x3 };
export const y4 = 1, x4 = 2;
// Aliases: the exported name by default.
export { b6 as a6x, a6 as b6x };
export { z7 as a7, b7 };
// String names.
export { a1 as 'b-8', b1 as 'a-8' };
// Type specifiers.
export { type T9, c1 as c9, type A9 };
// Re-exports.
export { y as y10, x as x10 } from './m10';
export type { Y11, X11 } from './m11';
// On several lines, with comments.
export {
  // the d
  d11,
  /* the b */
  b11, // after b
  a11,
};
// eslint-disable-next-line.
export {
  c12,
  // eslint-disable-next-line perfectionist/sort-named-exports
  a12,
  b12,
};
// Case.
export { b13, B13, a13, A13 };
