export {};
declare const textValue: string;
declare const numberValue: number;
const textConstant = 'constant';

// Consistent enums.
enum Numbers {
  A,
  B = 1,
  C = -1,
  D = numberValue,
}
enum Texts {
  A = 'a',
  B = `b`,
  C = textValue,
  D = textConstant,
}
enum Empty {}

// Mixed enums: the first member that does not match is reported.
enum NumberFirst {
  A = 1,
  B = 'b',
  C = 'c',
}
enum TextFirst {
  A = 'a',
  B = 2,
}
enum ImplicitNumber {
  A,
  B = 'b',
}
enum TextThenImplicit {
  A = 'a',
  B,
}
enum TemplateThenNumber {
  A = `a${textValue}`,
  B = 1,
}
enum ExpressionMix {
  A = numberValue,
  B = textValue,
}
enum Parenthesized {
  A = 1,
  B = ('b'),
}
enum QuotedNames {
  'a' = 1,
  'b' = 'b',
}

// Unknown members stop the check.
enum WithBigInt {
  A = 1n,
  B = 'b',
}

// Declarations that merge: later ones follow the first one with members.
enum Merged {
  A = 1,
}
enum Merged {
  B = 'b',
}
enum MergedText {
  A = 'a',
}
enum MergedText {
  B = 'b',
}
declare enum Ambient {
  A = 1,
  B = 'b',
}
const enum Constant {
  A = 'a',
  B = 1,
}
function scoped(): void {
  enum Local {
    A = 1,
    B = 'b',
  }
}

// Exported enums of namespaces follow the first declaration of the symbol.
namespace Space {
  export enum Inner {
    A = 'a',
  }
}
namespace Space {
  export enum Inner {
    B = 1,
  }
}
namespace Other {
  export enum Plain {
    A = 1,
    B = 'b',
  }
}
