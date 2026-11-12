// class-literal-property-style with 'getters': a readonly field initialized with a literal should
// be a getter, unless it is `declare` or `override`, or a constructor of its class assigns a member
// of `this` with the same static name; the suggestion writes the getter (decorators and other
// modifiers are dropped).
declare function dec(...args: unknown[]): any;
declare const styled: any, gql: any, myValue: any, p1: any;
declare abstract class Base {
  protected readonly overridden: string;
}
class Fields extends Base {
  readonly a = 'a';
  readonly b = `b`;
  readonly c = 1;
  readonly d = 10n;
  readonly e = null;
  readonly f = true;
  readonly g = /g/u;
  readonly h = ('parenthesized');
  readonly i = gql`query`;
  readonly j = `j ${1}`;
  readonly k = [1, 2, 3];
  readonly l = -1;
  readonly m;
  readonly n: string = 'typed';
  readonly o?: string = 'optional';
  readonly p! = 'definite';
  notReadonly = 'x';
  static readonly q = 'q';
  public static readonly r = 'r';
  protected readonly s = 's';
  private readonly t = 't'
  readonly #u = 'u';
  static readonly #v = 'v';
  readonly [myValue] = 'computed';
  readonly [/* before */ p1 /* after */] = 'commented';
  readonly ['str'] = 'str';
  readonly 'quoted' = 'quoted';
  readonly 42 = 42;
  @dec readonly decorated = 'decorated';
  declare readonly declared: 'declared';
  protected override readonly overridden = 'overridden';
  readonly withComment = 'c' /* trailing */;
  readonly lastOne = 'last' // no semicolon
  accessor accessorField = 'acc';
}
class Assigned {
  readonly a = 'a';
  readonly b = 'b';
  readonly c = 'c';
  readonly d = 'd';
  readonly e = 'e';
  readonly f = 'f';
  readonly g = 'g';
  readonly h = 'h';
  readonly i = 'i';
  readonly j = 'j';
  readonly k = 'k';
  readonly ['l'] = 'l';
  readonly [Symbol.iterator] = 'sym';
  readonly '' = 'empty';
  readonly m = 'm';
  readonly n = 'n';
  readonly #o = 'o';
  readonly o = 'o';
  constructor(other: Assigned) {
    this.a = 'A';
    this['b'] = 'B';
    this.c += 'C';
    delete this.d;
    (this.e as any) = 'E';
    this.f! = 'F';
    [this.g] = ['G'];
    [...this.h] = ['H'];
    ({ i: this.i } = { i: 'I' });
    (this.j) = 'J';
    this.k.length;
    this.l = 'L';
    this[Symbol.iterator] = 'SYM';
    this[''] = 'EMPTY';
    const arrow = () => {
      this.m = 'M';
    };
    function inner(this: Assigned) {
      this.n = 'N';
    }
    other.a = 'other';
    this.#o = 'O';
  }
}
class Nested {
  private readonly foo: string = 'bar';
  constructor(foo: string) {
    const bar = new (class {
      private readonly foo: string = 'baz';
      constructor() {
        this.foo = 'qux';
      }
    })();
    if (bar) {
      this.foo = 'baz';
    }
  }
}
class NotConstructor {
  readonly a = 'a';
  method() {
    this.a = 'A';
  }
  static {
    this.a = 'A';
  }
}
