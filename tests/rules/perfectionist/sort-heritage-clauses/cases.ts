interface A { a: 1 }
interface B { b: 1 }
interface C { c: 1 }
interface D { d: 1 }
declare namespace NS {
  interface Inner { i: 1 }
  interface Other { o: 1 }
}

// Sorted: nothing.
interface I1 extends A, B, C {}
class K1 implements A, B, C { a = 1 as const; b = 1 as const; c = 1 as const }

// Not sorted.
interface I2 extends C, A, B {}
class K2 implements C, B, A { a = 1 as const; b = 1 as const; c = 1 as const }

// One clause, or none.
interface I3 extends B {}
class K3 {}

// Qualified names are sorted by their last part.
interface I4 extends NS.Other, NS.Inner, A {}

// Type arguments.
interface G<T> { g: T }
interface H<T> { h: T }
interface I5 extends H<string>, G<number> {}

// On several lines, with comments.
interface I6 extends
  // the D one
  D,
  /* the B one */
  B, // after B
  A {}

// A class expression is not checked.
const k7 = class implements B, A { a = 1 as const; b = 1 as const };

// Case.
interface a { x: 1 }
interface I8 extends a, B, A {}

// eslint-disable-next-line.
interface I9 extends
  C,
  // eslint-disable-next-line perfectionist/sort-heritage-clauses
  A,
  B {}

// Partitions do not exist without the options.
interface I10 extends
  C,

  // comment
  A {}

export { k7 };
