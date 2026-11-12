// no-duplicate-enum-values: the values getMemberValue knows (string and number literals, `+` and
// `-` through Number(), templates without substitutions), compared with Object.is, and the ones
// it does not know.
enum Numbers {
  A = 1,
  B = 1,
  C = 0x1,
  D = 1.0,
  E = 1e0,
  F = 0b1,
  G = 0o1,
  H = 1_0,
  I = 10,
}

enum Zeros {
  A = 0,
  B = -0,
  C = +0,
  D = -(-0),
  E = -'',
  F = +'',
  G = 0.0,
}

enum Strings {
  A = 'a',
  B = "a",
  C = `a`,
  D = '\x61',
  E = `a`,
  F = 'b',
  // A comment between members.
  G = 'b',
  'quoted name' = 'b',
}

enum Mixed {
  A = '1',
  B = 1,
  C = +'1',
  D = -'1',
  E = -1,
  F = -'0x10',
  G = -16,
  H = - - 2,
  I = 2,
}

enum Big {
  A = 1e21,
  B = 1000000000000000000000,
  C = 0.1,
  D = .1,
  E = 1e-7,
  F = 0.0000001,
}

enum Parens {
  A = (3),
  B = ((3)),
  C = -(3),
  D = -3,
}

enum Unknown {
  A = 'a'.length,
  B = 'a'.length,
  C = `a${''}`,
  D = `a${''}`,
  E = -'x',
  F = -'x',
  G = ~1,
  H = ~1,
  I,
  J,
  K = A,
  L = A,
}

declare enum Declared {
  A = 'x',
  B = 'x',
}

const enum Constant {
  A = 5,
  B = 5,
}

namespace Outer {
  export enum Inner {
    A = 7,
    B = 7,
  }
}

export { Numbers, Zeros, Strings, Mixed, Big, Parens, Unknown, Outer };
