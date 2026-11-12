// prefer-destructuring: a variable that takes one property or one element of something.
interface Shape {
  foo: string;
  bar: number;
  0: string;
  baz: { qux: string };
  legacy: boolean;
}
declare const object: Shape;
declare const array: string[];
declare const tuple: [string, number];
declare const anyValue: any;
declare const text: string;
declare const union: string[] | Set<string>;
declare const mixedUnion: string[] | { 0: string };
declare const indexable: { [index: number]: string };
declare const index: number;
declare function getObject(label?: string): Shape;

function declarations() {
  const foo = object.foo;
  const bar = object['bar'];
  const baz = object.baz.qux;
  const qux = object.baz.qux;
  const renamed = object.foo;
  const first = array[0];
  const second = tuple[1];
  const fromAny = anyValue[0];
  const character = text[0];
  const zero = object[0];
  const indexed = indexable[0];
  const fromUnion = union[0];
  const fromMixedUnion = mixedUnion[0];
  const viaVariable = array[index];
  const negative = array[-1];
  const fraction = array[1.5];
  const big = array[0n];
  const stringIndex = array['0'];
  const exponent = array[1e0];
  const hexadecimal = array[0x1];
  const { length } = array;
  const [head] = array;
  var legacy = object.legacy;
  let uninitialized;
  return [foo, bar, baz, qux, renamed, first, second, fromAny, character, zero, indexed, fromUnion,
    fromMixedUnion, viaVariable, negative, fraction, big, stringIndex, exponent, hexadecimal, length,
    head, legacy, uninitialized];
}
function annotated() {
  const foo: string = object.foo;
  const first: string = array[0];
  const zero: string = object[0];
  const { bar }: Shape = object;
  const [head]: string[] = array;
  return [foo, first, zero, bar, head];
}
function expressions() {
  const foo = object?.foo;
  const bar = object!.bar;
  const baz = (object as Shape).baz;
  const legacy = (anyValue, object).legacy;
  const qux = getObject().baz.qux;
  return [foo, bar, baz, legacy, qux];
}
function comments() {
  const foo = /* before */ object.foo;
  const bar = object /* between */.bar;
  const baz = getObject(/* inside */ 'x').baz;
  const legacy = (object.legacy);
  const qux = object.baz[`qux`];
  const template = object[`foo`];
  return [foo, bar, baz, legacy, qux, template];
}
function assignments() {
  let foo;
  let bar;
  let first;
  let other;
  let zero;
  let count = 0;
  foo = object.foo;
  bar = object['bar'];
  first = array[0];
  other = object.foo;
  zero = object[0];
  count += object.bar;
  ({ foo } = object);
  [first] = array;
  (foo) = object.foo;
  object.baz.qux = object.foo;
  array[0] = array[1];
  foo = getObject().foo;
  foo = object?.foo;
  return [foo, bar, first, other, zero, count];
}
class Base {
  foo = 'base';
  0 = 'zero';
}
class Derived extends Base {
  #secret = 1;
  bar = 2;
  method() {
    const foo = super.foo;
    const secret = this.#secret;
    const bar = this.bar;
    const zero = super[0];
    let later;
    later = this.bar;
    return [foo, secret, bar, zero, later];
  }
}
async function disposables(holder: { resource: Disposable; items: Disposable[] }) {
  using resource = holder.resource;
  using first = holder.items[0];
  await using other = holder.items[1];
  return [resource, first, other];
}
for (let first = array[0], foo = object.foo; index < 1; ) {
  void first;
  void foo;
}
export { declarations, annotated, expressions, comments, assignments, Derived, disposables };
