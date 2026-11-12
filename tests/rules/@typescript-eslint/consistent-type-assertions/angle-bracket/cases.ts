declare const x: any;
type Foo<T = any> = any;
type A = any;
type B = any;
// Reported with assertionStyle 'angle-bracket' (no fix).
const a1 = x as Foo;
const a2 = x as const;
const a3 = { a: 1 } as Foo;
const a4 = x as (A | B);
const a5 = x as Foo<string>;
const a6 = x as /* c */ Foo;
const a7 = (x as Foo) as A;
const a8 = x as unknown as Foo;
// Not reported.
const b1 = <Foo>x;
const b2 = <const>[1];
export {};
