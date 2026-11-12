declare const x: any;
type Foo = any;
// Reported with assertionStyle 'never'.
const a1 = x as Foo;
const a2 = <Foo>x;
const a3 = { a: 1 } as Foo;
const a4 = [1] as Foo;
const a5 = x as any;
// Not reported: const assertions.
const b1 = x as const;
const b2 = <const>[1];
const b3 = [1] as const;
export {};
