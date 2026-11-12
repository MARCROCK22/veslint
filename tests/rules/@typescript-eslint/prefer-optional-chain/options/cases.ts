// prefer-optional-chain with requireNullish and every loose boolean check off.
interface Bar {
  baz?: { qux: number };
}
declare const foo: { bar?: Bar } | undefined;
declare const required: { bar: Bar };
declare const text: string | undefined;
declare const count: number | undefined;
declare const flag: true | undefined;
declare const big: bigint | undefined;
declare const anything: any;
declare const unknownValue: unknown;

// Reported: the checked values may be nullish.
foo && foo.bar;
foo && foo.bar && foo.bar.baz;
(foo || {}).bar;

// Not reported: without null or undefined in the checked values (requireNullish); for
// `foo != null` the checked value is the comparison, a boolean.
foo != null && foo.bar;
required && required.bar;
required.bar && required.bar.baz;
(required || {}).bar;

// Not reported: the loose boolean checks of these types are off.
text && text.length;
count && count.toFixed();
flag && flag.valueOf();
big && big.toString();
anything && anything.prop;
unknownValue && (unknownValue as Bar).baz;

// Reported: the first chain; `text` (a string, not checked) ends it.
foo && foo.bar && text && text.length;
