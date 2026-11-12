// prefer-readonly-parameter-types on constructs the grammar had to learn: an import type in an
// array, in parentheses and with a key; `abstract` and `out` as names; an optional destructured
// parameter in a function type; the signature of a default export.
function importTypes(
  a: import('./types').Mutable[],
  b: readonly import('./types').Frozen[],
  c: (import('./types').Mutable | undefined)[],
  d: import('./types').Table['row'],
  e: readonly (import('./types').Frozen)[],
  f: import('./types').Table['frozen'],
  g: (import('./types').Frozen),
  h: (import('./types').Mutable),
) {}
type Callback = ({ a }?: { a: number }, [b]?: readonly number[]) => void;
interface WithAbstract {
  abstract: string[];
  method(abstract: string[], other: readonly string[]): void;
}
class Holder {
  abstract = 1;
  set(abstract: number[]) {}
}
function named<out>(a: out[], b: readonly out[]) {}
export default function (a: string[], b: readonly string[]): void;
export default function (a: string[]) {}
// A type query of an import type, also in parentheses with a qualifier, and an import type with
// type arguments.
function typeQueries(
  a: typeof import('./types'),
  b: (typeof import('./types').mutableValue)[],
  c: readonly (typeof import('./types').mutableValue)[],
  d: typeof import('./types').frozenValue,
  e: (typeof import('./types').frozenValue),
  f: import('./types').Holder<string>,
  g: Readonly<import('./types').Holder<number>>,
  h: readonly import('./types').Holder<string>[],
) {}
export { importTypes, named, Holder, typeQueries };
export type { Callback, WithAbstract };
