// Exports with a source are sorted by it.
export { b } from './b';
export * from './a';
export type { T } from './t';
export * as ns from './c';
// Exports without a source are not, and do not end the part.
const x = 1;
export { x };
export const y = 2;
export { z } from './0-z';
// A comment and a multiline export.
export {
  m1,
  m2,
} from './m'; // after m
/* before l */
export { l } from './l';
// eslint-disable-next-line.
// eslint-disable-next-line perfectionist/sort-exports
export { k } from './k';
export type * from './j';
export { "s'1" } from "./s";
