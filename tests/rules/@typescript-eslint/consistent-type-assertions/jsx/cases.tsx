type Foo = any;
declare const x: any;
declare function Comp(props: any): any;
// Not reported: a JSXExpressionContainer is a parameter.
const a1 = <Comp style={{ bar: 5 } as Foo} />;
const a2 = <Comp items={[5] as Foo} />;
const a3 = <div>{{ a: 1 } as Foo}</div>;
// Reported.
const a4 = <Comp {...({ a: 1 } as Foo)} />;
const a5 = { a: 1 } as Foo;
const a6 = <Comp prop={(() => ({} as Foo))()} />;
export {};
