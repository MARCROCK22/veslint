// no-this-alias with allowDestructuring: false: destructurings and any other target that is not an
// identifier are reported too, with thisDestructure.
declare function use(value: unknown): void;

export class Foo {
  value = 1;
  method(): void {
    const self = this;
    const { value } = this;
    const { value: renamed, ...others } = this;
    const [first] = this as unknown as number[];
    const [second] = this;
    let target: { a?: unknown } = {};
    target.a = this;
    target['a'] = this;
    ({ value: target } = this);
    [target] = this;
    (target).a = this;
    use([self, value, renamed, others, first, second]);
  }
}
