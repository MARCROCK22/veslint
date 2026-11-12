// prefer-enum-initializers: the members without an initializer, with three suggestions each (the
// index of the member among the members, the comments aside, that index plus one, and its name
// quoted).
enum Direction {
  Up,
  // A comment does not count as a member.
  Down = 2,
  Left,
  Right,
}

enum Quoted {
  'with space',
  plain,
}

const enum Empty {}

declare enum Declared {
  A,
}

enum AllSet {
  A = 1,
  B = 'b',
}

export { Direction, Quoted, Declared, AllSet };
export type { Empty };
