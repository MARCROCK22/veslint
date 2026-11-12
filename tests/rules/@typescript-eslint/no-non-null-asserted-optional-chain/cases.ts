// no-non-null-asserted-optional-chain: a `!` at the end of an optional chain, and a `!` on a chain
// in parentheses.
declare const x: { y?: { z: number } } | undefined;
declare const fn: (() => { a: number }) | undefined;

x?.y!;
(x?.y)!;
((x?.y))!;
x?.y!!;
(x?.y!)!;
fn?.()!;
(fn?.())!;
x?.y?.z!;
x?.['y']!;
(x?.y)!!;

// The chain goes on after the `!`, or there is no `?.`.
x?.y!.z;
(x?.y)!.z;
x!?.y;
x!.y!;
fn!()!;
