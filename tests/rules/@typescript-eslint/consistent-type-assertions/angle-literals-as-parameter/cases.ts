declare const x: any;
declare function foo(...args: any[]): any;
declare function tag(...args: any[]): any;
declare class Bar {
  constructor(...args: any[]);
}
type Foo = any;
declare namespace Foo {
  type Bar = any;
}
const a1 = <Foo>{};
const a2 = <Foo>({ a: 1 });
const a3 = (<Foo>{ a: 1 });
let a4 = <Foo>{}, a5: Foo = <Foo>{};
const a6 = <any>{};
const a7 = <unknown>{};
const a8 = <const>{};
const a9 = <Foo.Bar>{};
const { a10 } = <Foo>{};
const a11 = <Foo>[];
const a12 = <Foo>([1, 2]);
const a13 = <any>[];
const a14 = <const>[1];
const [a15] = <Foo>[1];
foo(<Foo>{}, <Foo>[]);
new Bar(<Foo>{}, <Foo>[]);
function f1(a = <Foo>{}, b = <Foo>[]) {}
function f2() {
  throw <Foo>{};
}
tag`${<Foo>{}}${<Foo>[]}`;
`${<Foo>{}}${<Foo>[]}`;
let v: any;
v = <Foo>{};
v = <Foo>[];
const a16 = {} as Foo;
export {};
