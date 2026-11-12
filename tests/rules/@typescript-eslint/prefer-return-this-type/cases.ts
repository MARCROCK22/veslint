// prefer-return-this-type: methods and function properties of a class that only return `this`.
declare function decorate<T>(value: T, context: unknown): T;

export class Basic {
  // Reported: only `this` is returned.
  self(): Basic {
    return this;
  }

  // Reported at the class name inside a union.
  maybe(): Basic | undefined {
    if (Math.random() > 0.5) {
      return this;
    }
    return undefined;
  }

  // Not reported: it also returns an instance of the class.
  mixed(): Basic {
    if (Math.random() > 0.5) {
      return this;
    }
    return new Basic();
  }

  // Reported: a call that returns `this` has the `this` type.
  chained(): Basic {
    return this.fluent();
  }

  fluent(): this {
    return this;
  }

  // Not reported: `self()` is declared to return the class type.
  viaSelf(): Basic {
    return this.self();
  }

  // Not reported: the return type does not name the class.
  other(): object {
    return this;
  }

  // Not reported: an explicit `this` parameter.
  withThis(this: Basic): Basic {
    return this;
  }

  // Reported: arrow function property.
  arrow = (): Basic => this;

  // Reported: arrow function property with a block body.
  arrowBlock = (): Basic => {
    return this;
  };

  // Not reported: a function expression property whose first parameter is `this`.
  func = (function (this: Basic): Basic {
    return this;
  });

  // Reported: function expression property (parenthesized value).
  funcNoThis = (function (): Basic {
    // @ts-expect-error -- `this` is implicitly `any` in a function expression.
    return this;
  });

  // Reported: accessor property.
  accessor acc = (): Basic => this;

  // Reported: getter with a parenthesized return type.
  get getter(): (Basic) {
    return this;
  }

  // Not reported: no return statement with `this`.
  none(): Basic {
    return new Basic();
  }

  // Not reported: the union also includes the class type.
  unionReturn(flag: boolean): Basic | null {
    return flag ? this : null;
  }

  // Reported: the union return type lists the class second; returns nested in statements.
  nested(kind: number): null | Basic {
    label: for (const item of [1, 2]) {
      switch (kind + item) {
        case 1:
          try {
            return this;
          } catch {
            return this;
          } finally {
            kind++;
          }
        default:
          while (kind > 10) {
            do {
              return this;
            } while (kind > 20);
          }
          continue label;
      }
    }
    return this;
  }

  // Not reported: the returns of nested functions are not visited, so only `return null` counts.
  inner(): Basic | null {
    function helper(this: Basic): Basic {
      return new Basic();
    }
    const arrow = () => {
      return this;
    };
    void helper;
    void arrow;
    return null;
  }

  // Not reported: an expression body that is not `this`.
  notThis = (): Basic => new Basic();

  /* 😀 */ emoji(): Basic { return this; }

  // Reported: a static method returning `this` (the constructor) passes the fast check.
  static create(): Basic {
    // @ts-expect-error -- `typeof Basic` is not `Basic`.
    return this;
  }

  // Not reported: the assertion has the class type.
  static make(): Basic {
    return this as unknown as Basic;
  }
}

// Generic class: reported for `Gen<T>`, not when it returns `new Gen<T>()`.
class Gen<T> {
  value?: T;
  self(): Gen<T> {
    return this;
  }
  copy(): Gen<T> {
    return new Gen<T>();
  }
  other(): Gen<number> {
    return this as unknown as Gen<number>;
  }
}

// Abstract class: abstract members are not visited.
abstract class Shape {
  abstract area(): Shape;
  abstract clone: () => Shape;
  resize(): Shape {
    return this;
  }
  overloaded(): Shape;
  overloaded(): Shape {
    return this;
  }
}

// Class expressions: the type of the class is its constructor type, without a `this` type.
const Named = class Expr {
  // Reported: `return this` is the fast check.
  self(): Expr {
    return this;
  }
  // Not reported: a parenthesized `this` is checked by type.
  paren(): Expr {
    return (this);
  }
  // Not reported: an expression body is checked by type.
  arrow = (): Expr => this;
};

const Anonymous = class {
  self(): object {
    return this;
  }
};

// Exported, default-exported and decorated classes.
export default class Defaulted {
  self(): Defaulted {
    return this;
  }
}

@decorate
class Decorated {
  self(): Decorated {
    return this;
  }
}

@decorate
export class DecoratedExported {
  self(): DecoratedExported {
    return this;
  }
}

// A nested class is checked with its own name.
class Outer {
  method(): Outer {
    class Inner {
      self(): Inner {
        return this;
      }
    }
    void Inner;
    return this;
  }
}

// Object literal methods are not class members.
const literal = {
  self(): object {
    return this;
  },
};

void Named;
void Anonymous;
void literal;
void Gen;
void Shape;
void Decorated;
void Outer;
