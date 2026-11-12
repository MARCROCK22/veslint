namespace Outer {
  export type Name = string;
  export const value = 1;
  export namespace Inner {
    export type Deep = number;
    type InsideInner = Outer.Inner.Deep;
    const fromInner = Outer.value;
  }
  type Alias = Outer.Name;
  const copy = Outer.value;
  type Nested = Outer.Inner.Deep;
  type Query = typeof Outer.value;
  import Imported = Outer.Inner;
  function shadow(value: number): number {
    return Outer.value + value;
  }
  const chained = Outer.value.toFixed();
  const optional = Outer?.value;
  const parenthesized = (Outer).value;
  type Generic = Array<Outer.Name>;
  class Member {
    field = Outer.value;
  }
  import Self = Outer;
  const throughAlias = Self.value;
}

enum Letter {
  A = 1,
  B = Letter.A,
}

export enum ExportedLetter {
  A = 1,
  B = ExportedLetter.A,
}

declare const enum ConstLetter {
  A = 1,
  B = ConstLetter.A,
}

export namespace Exported {
  export const item = 1;
  const again = Exported.item;
}

declare namespace Ambient {
  const item: number;
  const again: typeof Ambient.item;
}

namespace Merged {
  export const first = 1;
}
namespace Merged {
  const second = Merged.first;
}

// Dotted namespaces: only the outermost one is in scope.
namespace Dotted.Child {
  export const leaf = 1;
  const viaChild = Dotted.Child.leaf;
  const viaParent = Dotted.Child;
}
export namespace ExportedDotted.Child {
  export const leaf = 1;
  const viaChild = ExportedDotted.Child.leaf;
}

// A local declaration shadows the namespace member.
namespace Shadowed {
  export const item = 1;
  function inner(): number {
    const item = 2;
    return Shadowed.item + item;
  }
}

// Outside the namespace the qualifier is needed.
type Outside = Outer.Name;
const outside = Outer.value;

export type { Outside };
export { outside };
