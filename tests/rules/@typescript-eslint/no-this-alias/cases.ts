// no-this-alias with its default options (allowDestructuring: true, allowedNames: []): `this` as
// the initializer of a variable or the right side of an assignment, when the target is an
// identifier; destructurings and other targets are allowed.
declare function use(value: unknown): void;

export class Foo {
  value = 1;
  method(): void {
    const self = this;
    let that;
    that = this;
    var parens = (this);
    let other: Foo | undefined;
    other ||= this;
    other ??= this;
    (that) = this;
    const typed: this = this;
    const /* before */ commented /* after */ = /* value */ this;
    const { value } = this;
    const [first] = this as unknown as number[];
    let rest;
    ({ value: rest } = this);
    [rest] = this as unknown as number[];
    const holder = { a: this as unknown };
    holder.a = this;
    holder['a'] = this;
    use([first, rest, self, typed, commented, value, parens]);
  }
}

function inFunction(this: Foo): void {
  const inner = this;
  const asserted = this as Foo;
  const nonNull = this!;
  const called = use(this);
  const arrow = () => this;
  const array = [this];
  const text = 'this';
  use([inner, asserted, nonNull, called, arrow, array, text]);
}

class WithDefaults {
  method(scope: this = this): void {
    use(scope);
  }
  field = this;
}

for (const loop = this; ; ) {
  break;
}
