// no-this-alias with allowedNames ["self", "that"]: those names may alias `this`; destructurings are
// still allowed (allowDestructuring defaults to true).
declare function use(value: unknown): void;

export class Foo {
  value = 1;
  method(): void {
    const self = this;
    let that;
    that = this;
    const me = this;
    const Self = this;
    const { value } = this;
    use([self, that, me, Self, value]);
  }
}
