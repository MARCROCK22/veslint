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
const a1 = {} as Foo;
const a2 = ({ a: 1 }) as Foo;
const a3 = ({ a: 1 } as Foo);
let a4 = {} as Foo, a5: Foo = {} as Foo;
const a6 = {} as any;
const a7 = {} as unknown;
const a8 = {} as const;
const a9 = {} as Foo.Bar;
const a10 = {} as Foo as Foo;
const { a11 } = {} as Foo;
const a12 = {
  a: 1, // comment
} as Foo;
const a13 = { /* c */ } as /* d */ Foo;
foo({} as Foo);
new Bar({} as Foo);
foo?.({} as Foo);
(({} as Foo))();
function f1(a = {} as Foo) {}
const [b1 = {} as Foo] = [];
const { b2 = {} as Foo } = {};
function f2() {
  throw {} as Foo;
}
tag`${{} as Foo}`;
`${{} as Foo}`;
import({} as Foo);
let v: any;
v = {} as Foo;
const a14 = [] as Foo;
const a15 = ([1, 2]) as Foo;
const a16 = [] as any[];
const a17 = [] as unknown;
const a18 = [1] as const;
let a19 = [] as Foo, a20: Foo = [] as Foo;
const [a21] = [1] as Foo;
foo([] as Foo);
new Bar([] as Foo);
function f3(a = [] as Foo) {}
function f4() {
  throw [] as Foo;
}
tag`${[] as Foo}`;
`${[] as Foo}`;
v = [] as Foo;
const a22 = <Foo>{};
export {};
