// no-unnecessary-qualifier: the fix removes from the start of the qualifier to the start of the
// name. Non-ASCII text before the ranges: ñ 😀 日本語.
namespace Outer {
  export type Name = string;
  export const value = 1;
  export namespace Inner {
    export type Deep = number;
    export const deep = 2;
    type FromInner = Outer.Inner.Deep;
    const fromInner = Inner.deep;
  }
  // Qualified names in types and member accesses in expressions.
  type A1 = Outer.Name;
  const a2 = Outer.value;
  type A3 = Outer.Inner.Deep;
  const a4 = Outer.Inner.deep;
  // What is between the qualifier and the name goes too.
  type B1 = Outer /* a */ . /* b */ Name;
  const b2 = Outer
    .value;
  const b3 = Outer . value;
  const b4 = Outer. // dot first
    value;
  // Parentheses are not part of the qualifier: the range starts inside them.
  const c1 = (Outer).value;
  const c2 = ((Outer)).value;
  // An optional chain, a type query and a type argument.
  const d1 = Outer?.value;
  type D2 = typeof Outer.value;
  type D3 = Array<Outer.Name>;
  // Non-ASCII text on the same line.
  const ñ = '😀'; const e1 = Outer.value; type 日本 = Outer.Name;
}

enum Letter {
  A = 1,
  B = Letter.A,
  C = Letter /* c */ . A,
}
