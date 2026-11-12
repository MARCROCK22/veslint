type Foo = any;
declare const x: any;
declare function Comp(props: any): any;
// Reported with assertionStyle 'angle-bracket' in a .tsx file.
const a1 = <Comp style={{ bar: 5 } as Foo} />;
const a2 = x as Foo;
export {};
