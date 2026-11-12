// prefer-optional-chain with the default options.
interface Baz {
  buzz?: { qux: number };
  call(): Baz | undefined;
  list: number[];
}
interface Bar {
  baz?: Baz;
  fn?: () => number;
  value?: number | null;
  text: string;
}
interface Foo {
  bar?: Bar;
  'a-b'?: Bar;
  method(): Bar | undefined;
}
declare const foo: Foo | undefined;
declare const nullable: Foo | null;
declare const both: Foo | null | undefined;
declare const required: Foo;
declare const other: Foo | undefined;
declare const fn: (() => number) | undefined;
declare const text: string | undefined;
declare const count: number | undefined;
declare const flag: boolean | undefined;
declare const big: bigint | undefined;
declare const anything: any;
declare const unknownValue: unknown;
declare const falseOrObject: false | { a: string };
declare const emptyOrObject: '' | { a: string };
declare const zeroOrObject: 0 | { a: string };
declare const zeroBigOrObject: 0n | { a: string };
declare const key: 'bar';
declare const promise: Promise<Foo | undefined>;

// Reported: && chains of truthiness checks.
foo && foo.bar;
foo && foo.bar && foo.bar.baz;
foo && foo.bar && foo.bar.baz && foo.bar.baz.buzz;
foo && foo.method();
fn && fn();
foo && foo['bar'];
foo && foo[key];
foo && foo['a-b'];
foo.bar && foo.bar.baz;
foo && foo.bar && foo.bar.fn && foo.bar.fn();
text && text.length;
count && count.toFixed();
big && big.toString();
anything && anything.prop;
/* 😀 */ foo && foo.bar;

// Reported: nullish comparisons.
foo != null && foo.bar;
foo != undefined && foo.bar;
foo !== undefined && foo.bar;
nullable !== null && nullable.bar;
both !== null && both !== undefined && both.bar;
both !== undefined && both !== null && both.bar;
null != foo && foo.bar;
undefined !== foo && foo.bar;
typeof foo !== 'undefined' && foo.bar;
typeof foo.bar !== 'undefined' && foo.bar.baz;

// Reported: the last operand compares the chained value.
foo && foo.bar != null;
foo && foo.bar !== undefined;
foo && foo.bar && foo.bar.value === 1;
foo && foo.bar && 1 === foo.bar.value;
foo && foo.bar && typeof foo.bar.baz !== 'undefined';
foo && foo.bar && foo.bar.text !== 'x';

// Reported: || chains of negations.
!foo || !foo.bar;
!foo || !foo.bar || !foo.bar.baz;
!foo || foo.bar === undefined;

// Reported: parenthesized operands (the report starts at the parenthesis).
(foo) && foo.bar;
((foo)) && foo.bar && (foo.bar.baz);
(foo && foo.bar) && foo.bar.baz;

// Reported: two chains in one expression, and a chain after an unrelated operand.
foo && foo.bar && other && other.bar;
count && foo && foo.bar;

// Reported: `(foo || {}).bar` and `(foo ?? {}).bar`.
(foo || {}).bar;
(foo ?? {}).bar;
(foo || {})[key];
(foo || {}).method;
async function awaited() {
  return (await promise || {}).bar;
}

// Reported: existing optional chains and non-null assertions.
foo?.bar && foo.bar.baz;
foo && foo?.bar;
foo!.bar && foo!.bar.baz;
foo && foo.bar!.baz;

// Reported: calls, chains inside a mixed expression, and a chain compared with its root.
foo && foo.bar || other;
foo && foo.bar === foo;
foo && foo.method() && foo.method()!.text;
required.method() && required.method()!.baz;

// Not reported: falsy literal types the && check narrows away (`boolean` is `true | false`).
flag && flag.valueOf();
falseOrObject && falseOrObject.a;
emptyOrObject && emptyOrObject.a;
zeroOrObject && zeroOrObject.a;
zeroBigOrObject && zeroBigOrObject.a;

// Not reported: unrelated or non-member operands, nullish checks followed by a truthiness check
// in an || chain, mixed operators and private names.
both === null || both === undefined || both.bar;
nullable === null || nullable.bar;
foo === undefined || foo.bar;
foo == null || foo.bar;
unknownValue && (unknownValue as Foo).bar;
foo && other;
foo && other.bar;
foo.bar && foo.baz;
foo && foo;
foo && bar();
foo || foo.bar;
!foo && foo.bar;
foo === null && foo.bar;
foo != null || foo.bar;
typeof window === 'undefined' || window.foo;
foo && foo.#private;
function bar(): Foo | undefined {
  return undefined;
}
class WithPrivate {
  #value?: { a: number };
  check(): unknown {
    return this.#value && this.#value.a;
  }
}
void awaited;
void WithPrivate;
