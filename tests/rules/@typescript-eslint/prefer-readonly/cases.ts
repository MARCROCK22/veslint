// prefer-readonly: private members that are never reassigned.
declare const anyValue: any;
declare const list: number[];
declare function decorate(...args: unknown[]): any;
enum Color {
  Red,
  Blue,
}
export enum Exported {
  A = 'a',
  B = 'b',
}
namespace Ns {
  export enum Inner {
    X,
    Y,
  }
}

class Basic {
  private neverModified = 1;
  private modifiedInMethod = 1;
  private modifiedInConstructor = 1;
  private modifiedInCallback = 1;
  private incremented = 0;
  private decremented = 0;
  private deleted?: number;
  private compound = 1;
  private logical: number | undefined;
  private readonly alreadyReadonly = 1;
  public publicMember = 1;
  protected protectedMember = 1;
  private static staticNever = 1;
  private static staticModified = 1;
  private static readonly staticReadonly = 1;
  #hashNever = 1;
  #hashModified = 1;
  static #staticHash = 1;
  static #staticHashModified = 1;
  private declare declared: number;
  private uninitialized: number;
  private optional?: string;
  private arrow = () => 1;
  private func = function () {};
  private accessor auto = 1;
  private 'quoted' = 1;
  private 123 = 1;
  private [456] = 1;
  private ['computedString'] = 1;
  private [Symbol.iterator] = 1;
  private typed: number = 1;
  private widened = 1;
  private text = 'text';
  private flag = true;
  private big = 10n;
  private nothing = null;
  private object = { a: 1 };
  private color = Color.Red;
  private exported = Exported.A;
  private inner = Ns.Inner.X;
  private sameLiteral = 1 as const;

  constructor() {
    this.modifiedInConstructor = 2;
    this.uninitialized = 3;
    this.widened = 2;
    this.text = 'other';
    this.flag = false;
    this.big = 20n;
    this.nothing = null;
    this.object = { a: 2 };
    this.color = Color.Blue;
    this.exported = Exported.B;
    this.inner = Ns.Inner.Y;
    this.typed = 2;
    this.sameLiteral = 1;
    this.#hashNever = 2;
    [1].forEach(() => {
      this.modifiedInCallback = 2;
    });
    Basic.staticModified = 2;
  }
  method() {
    this.modifiedInMethod = 2;
    this.incremented++;
    --this.decremented;
    delete this.deleted;
    this.compound += 1;
    this.logical ??= 1;
    this.#hashModified = 2;
    Basic.#staticHashModified = 2;
    return [this.neverModified, this.arrow, this.func, this.optional, Basic.staticNever, Basic.#staticHash];
  }
}

class Destructuring {
  private a = 1;
  private b = 1;
  private c = 1;
  private d = 1;
  private e = 1;
  private f = 1;
  private g = 1;
  private h = 1;
  private i = 1;
  private j = 1;
  private k = 1;
  private l = 1;
  private m = 0;
  private n = 1;
  private o = 1;
  private p = 1;
  private q = 1;
  private r = 1;
  method(other: Destructuring) {
    [this.a] = list;
    ({ x: this.b } = anyValue);
    [...this.c] = list;
    ({ ...this.d } = anyValue);
    [this.e = 2] = list;
    ({ x: [this.f] } = anyValue);
    [[this.g]] = anyValue;
    (this.h) = 2;
    this.i! = 2;
    (this.j) += 2;
    this['k'] = 2;
    this[`l`]++;
    list[this.m] = 2;
    for (this.n of list) {
    }
    other.o = 2;
    (this.p as number) = 2;
    [...[this.q]] = list;
  }
}

class Parameters {
  constructor(
    private never: number,
    private modified: number,
    private readonly already: number,
    public open: number,
    protected guarded: number,
    private withDefault = 1,
    private callback = () => 1,
    private optional?: string,
    @decorate private decorated?: number,
    plain?: number,
  ) {
    this.modified = 2;
  }
  change() {
    this.modified = 3;
    return [this.never, this.withDefault, this.callback, this.optional, this.decorated];
  }
}
class ParameterOnlyInConstructor {
  constructor(private value: number) {
    this.value = 2;
  }
}
class Decorated {
  @decorate
  private field = 1;
  @decorate private inline = 1;
  @decorate
  @decorate
  private static shared = 1;
}
class Statics {
  private static count = 0;
  private static total = 0;
  private instance = 0;
  static bump() {
    this.count++;
    Statics.total += 1;
  }
  touch(other: Statics) {
    other.instance = 1;
  }
  static {
    Statics.count = 5;
  }
}
class Inheritance extends Basic {
  private own = 1;
  private shadow = 1;
  method() {
    this.shadow = 2;
    return [this.own];
  }
}
class Outer {
  private outerValue = 1;
  private touchedByInner = 1;
  build() {
    const outer = this;
    return class Inner {
      private innerValue = 1;
      private innerModified = 1;
      run() {
        outer.touchedByInner = 2;
        this.innerModified = 2;
        return [this.innerValue];
      }
    };
  }
}
const Expression = class {
  private value = 1;
  private changed = 1;
  constructor() {
    this.value = 2;
  }
  set() {
    this.changed = 2;
  }
};
export default class {
  private anonymous = 1;
}
class Generic<T> {
  private item: T | undefined;
  private fixed = 1;
  set(value: T, other: Generic<T>, another: Generic<string>) {
    other.item = value;
    another.fixed = 2;
  }
}
class Union {
  private left = 1;
  private right = 1;
  mutate(target: Union | Basic, either: Basic | Union) {
    (target as any).left = 2;
    target.left = 3;
    either.right = 4;
  }
}
abstract class Abstract {
  private concrete = 1;
  abstract run(): void;
}
class Overloaded {
  constructor(a: string);
  constructor(private a: unknown) {}
  private later = 1;
  private early = 1;
  init() {
    this.later = 2;
  }
}
class ConstructorNested {
  private inArrow = 1;
  private inFunction = 1;
  private inObjectMethod = 1;
  private inGetter = 1;
  private direct = 1;
  private inDefault = 1;
  constructor(value = (this.inDefault = 2)) {
    this.direct = 2;
    const arrow = () => {
      this.inArrow = 2;
    };
    const self = this;
    function declared() {
      self.inFunction = 2;
    }
    const object = {
      method: () => {
        this.inObjectMethod = 2;
      },
      get getter() {
        self.inGetter = 2;
        return 1;
      },
    };
    void [arrow, declared, object, value];
  }
}
class WithComments {
  private /* before */ commented = 1;
  private
  multiline = 1;
}
export { Basic, Destructuring, Parameters, ParameterOnlyInConstructor, Decorated, Statics, Inheritance, Outer, Expression, Generic, Union, Abstract, Overloaded, ConstructorNested, WithComments };
