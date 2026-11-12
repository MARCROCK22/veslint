// dot-notation with allowKeywords: false.
declare const a: Record<string, number>;
declare const nested: { class: { if: number } } | undefined;

// Reported: keywords after a dot.
a.class;
a.default;
a.if;
nested?.class.if;

// Not reported: keyword keys in brackets, and non-keywords.
a['class'];
a['default'];
// @ts-expect-error -- `true` is not a valid index type.
a[true];
a.foo;
a.yield;

// Reported: other identifier keys in brackets.
a['foo'];
a[`bar`];

// Not reported: `typeof a.class` is a qualified name.
type K = typeof nested;
let x: typeof a.class;
void x;
void (null as unknown as K);
