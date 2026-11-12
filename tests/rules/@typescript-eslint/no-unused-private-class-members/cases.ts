// no-unused-private-class-members: a `private` or `#private` member that is never read (an
// accessor that is only written counts as used).
declare const list: number[][];
declare const obj: Record<string, unknown>;
declare function use(...values: unknown[]): void;

class Unused {
  #a = 1;
  private b = 2;
  private static c = 3;
  static #d = 4;
  protected e = 5;
  public f = 6;
  g = 7;
  private declare h: number;
  private 'quoted' = 8;
  private 9 = 9;
  private ['computed'] = 10;
  private [`template`] = 11;
  private [Symbol.iterator] = 12;
  private i() {}
  #j() {}
  private get k() {
    return 1;
  }
  set #l(value: number) {
    use(value);
  }
}

class Reads {
  #a = 1;
  private b = 2;
  private 'c' = 3;
  private 4 = 4;
  private [`e`] = 5;
  #f = 6;
  private g = 7;
  #h = 8;
  #i = 9;
  private j = 10;
  m() {
    use(this.#a, this.b, this['c'], this[4], this[`e`], #f in obj, this?.g, this.#h?.toString());
    use(typeof this.#i, (this.j));
  }
}

class Writes {
  #a = 1;
  private b = 2;
  #c = 3;
  private d = 4;
  #e: number[] = [];
  private f: number[] = [];
  #g = 0;
  private h = 0;
  #i = 0;
  private j = 0;
  #k = 0;
  private l = 0;
  m() {
    this.#a = 1;
    this.b += 1;
    this.#c++;
    --this.d;
    for (this.#e of list) {
    }
    for (this.f in obj) {
    }
    ({ x: this.#g } = { x: 1 });
    [this.h] = [1];
    [...this.#i] = [1];
    [this.j = 1] = [];
    (this.#k) = 2;
    ({ ...this.l } = {});
  }
}

class WritesThatRead {
  #a = 1;
  private b = 2;
  #c = 3;
  private d = 4;
  #e = 5;
  private f = 6;
  m() {
    let x = (this.#a += 1);
    use(this.b++);
    use((this.#c = 1));
    ({ [this.d]: x } = { x: 1 });
    this.#e!++;
    for (const y of [this.f]) {
      use(x, y);
    }
  }
}

class Accessors {
  get #a() {
    return 1;
  }
  set #a(value: number) {
    use(value);
  }
  private set b(value: number) {
    use(value);
  }
  private get c() {
    return 1;
  }
  private set c(value: number) {
    use(value);
  }
  accessor #d = 1;
  private accessor e = 2;
  private accessor f = 3;
  private static accessor g = 4;
  m() {
    this.#a = 1;
    this.b = 2;
    this.c += 1;
    this.f = 3;
  }
}

class ParameterProperties {
  constructor(
    private a: number,
    private readonly b = 1,
    public c: number,
    private d?: string,
    protected e = 2,
    readonly f = 3,
  ) {}
  m() {
    return this.d;
  }
}

class Statics {
  private static a = 1;
  private static b = 2;
  private static c = 3;
  private static d = 4;
  private static e = 5;
  static f = this.d;
  static #g = 6;
  static m() {
    return [this.a, Statics.b];
  }
  n() {
    return [this.c, Statics.#g];
  }
  static {
    use(this.e);
  }
}

class Aliases {
  private a = 1;
  private b = 2;
  private c = 3;
  private d = 4;
  private e = 5;
  m() {
    const self = this;
    let other = this;
    other = new Aliases();
    const self1 = this;
    const self2 = self1;
    const notThis = new Aliases();
    use(self.a, other.b, self2.c, notThis.d, (self).e);
  }
}

class Typed<T> {
  private a = 1;
  private b = 2;
  private static c = 3;
  private d = 4;
  private e = 5;
  private f = 6;
  private static g = 7;
  m(one: Typed<T>, two: (Typed<T>), three: typeof Typed, four = new Typed<T>(), ...five: Typed<T>[]) {
    use(one.a, two.b, three.c, four.d, five[0].e);
    try {
      use(one);
    } catch (error: Typed<number>) {
      use(error.f);
    }
  }
  static n(this: typeof Typed) {
    return this.g;
  }
}

class Destructuring {
  private a = 1;
  private b = 2;
  private c = 3;
  private d = 4;
  private e = 5;
  private f = 6;
  private g = 7;
  private h = 8;
  private static i = 9;
  m() {
    const { a } = this;
    const { b: renamed } = this;
    const { unused: c } = this;
    let d: number;
    ({ d } = this);
    const take = ({ e } = this) => e;
    const { ['f']: computed } = this;
    const { g = 1, ...rest } = this;
    use(a, renamed, c, d, take, computed, g, rest, this.h);
  }
  static n() {
    const { i } = this;
    return i;
  }
}

class Scopes {
  private a = 1;
  private b = 2;
  private c = 3;
  private d = 4;
  private e = 5;
  private f = 6;
  private g = 7;
  arrowField = () => this.a;
  functionField = function (this: unknown) {
    return (this as Scopes).b;
  };
  plainFunctionField = function () {
    return Scopes.prototype.c;
  };
  accessor accessorFunction = function () {
    return this.d;
  };
  m() {
    function inner() {
      return this.e;
    }
    function typed(this: Scopes) {
      return this.f;
    }
    const literal = {
      method(this: Scopes) {
        return this.g;
      },
    };
    return [inner, typed, literal];
  }
}

class FieldFunction {
  private a = 1;
  private static b = 2;
  read = function () {
    return this.a;
  };
  static readStatic = function () {
    return this.b;
  };
}

class Outer {
  #shadowed = 1;
  #usedInInner = 2;
  private notInInner = 3;
  m(other: Outer) {
    return class Inner {
      #shadowed = 4;
      n() {
        return [this.#shadowed, other.#usedInInner, other.notInInner];
      }
    };
  }
}

class Overloads {
  private a(): void;
  private a(value?: number) {
    use(value);
  }
  private b(): void;
  private b(value?: number) {
    use(value);
  }
  m() {
    this.b();
  }
}

const Expression = class {
  private a = 1;
  #b = 2;
};
const NamedExpression = class Named {
  private static a = 1;
  private b = 2;
  m() {
    return [Named.a, Named.b];
  }
};

export default class {
  #a = 1;
  private b = 2;
}

class Outside {
  private a = 1;
  private b = 2;
}
const outside = new Outside();
use(outside.a, outside['b']);

class TypeQuery {
  private a = 1;
  m() {
    let x: typeof this.a = 1;
    return x;
  }
}

export { Unused, Reads, Writes, WritesThatRead, Accessors, ParameterProperties, Statics, Aliases };
export { Typed, Destructuring, Scopes, FieldFunction, Outer, Overloads, Expression, NamedExpression, TypeQuery };
