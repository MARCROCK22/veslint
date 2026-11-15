// Sorted: nothing.
import { a1, b1, c1 } from './m1';
// Not sorted.
import { c2, a2, b2 } from './m2';
// One specifier, a default and a namespace.
import d3, { x3 } from './m3';
import * as ns4 from './m4';
// A default import is not sorted with the named ones.
import z5, { b5, a5 } from './m5';
// Aliases: the local name by default.
import { b6 as a6, a6 as b6 } from './m6';
import { a7 as z7, b7 } from './m7';
// String names.
import { 'b-8' as b8, 'a-8' as a8 } from './m8';
// Type specifiers.
import { type T9, c9, type A9 } from './m9';
import type { Y10, X10 } from './m10';
// On several lines, with comments.
import {
  // the d
  d11,
  /* the b */
  b11, // after b
  a11,
} from './m11';
// eslint-disable-next-line.
import {
  c12,
  // eslint-disable-next-line perfectionist/sort-named-imports
  a12,
  b12,
} from './m12';
// Case.
import { b13, B13, a13, A13 } from './m13';
export { a1, b1, c1, a2, b2, c2, d3, x3, ns4, z5, a5, b5, a6, b6, z7, b7, a8, b8, c9, a11, b11, d11, a12, b12, c12, a13, A13, b13, B13 };
export type { T9, A9, X10, Y10 };
