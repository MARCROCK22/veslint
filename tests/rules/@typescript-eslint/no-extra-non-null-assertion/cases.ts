// no-extra-non-null-assertion: a `!` on another `!`, and a `!` right before an element's own `?.`,
// through parentheses (which ESTree does not have).
declare const a: { b?: { c(): number } } | undefined;
declare const f: (() => number) | undefined;
declare const xs: number[] | undefined;
declare const h: { i?: () => number } | undefined;

a!!;
a!!!;
(a!)!;
((a!))!;
a!?.b;
a!!?.b;
(a!)?.b;
xs!?.[0];
f!?.();
(f!)?.();
a?.b!!;
a?.b!?.c();
a /* between */ ! !;

// Not extra.
a!.b!;
f!();
a?.b!;
a?.b!.c();
xs![0]!;
const g = a! as unknown;
export { g };

// A `!` that ends an optional chain in parentheses is inside a ChainExpression in ESTree.
(a?.b!)!;
((a?.b!))!;
(a?.b!)?.c();
(xs?.[0]!)!;
(h?.i!)?.();
(h?.i!)!!;
