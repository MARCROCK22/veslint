declare const x: any, y: any, z: any;
declare function foo(...args: any[]): any;
declare class Bar {
  constructor(...args: any[]);
}
type Foo = any;
declare namespace Foo {
  type Bar = any;
}
type A = any;
type B = any;
// Reported with the default options (assertionStyle 'as'), and fixed.
const a1 = <Foo>x;
const a2 = <Foo>(x);
const a3 = <Foo>(x + y);
const a4 = <Foo>(x, y);
const a5 = <Foo>(x ? y : z);
const a6 = <Foo>(x = y);
const a7 = <Foo>(() => x);
const a8 = <Foo>x!;
const a9 = <Foo>x.y;
const a10 = <Foo>x?.y;
const a11 = <Foo>x[0];
const a12 = <Foo>foo();
const a13 = <Foo>new Bar();
const a14 = <Foo>new Bar;
const a15 = <Foo>`template`;
const a16 = <Foo>-x;
const a17 = <Foo>!x;
const a18 = <Foo>typeof x;
const a20 = <Foo><Bar>x;
const a21 = <Foo>(x as Bar);
const a22 = <Foo>(x in y);
const a23 = <Foo>(x || y);
const a24 = <Foo>(x ?? y);
const a26 = <const>[1, 2];
const a27 = <Foo>(<Bar>x);
const a28 = <Foo.Bar>x;
const a29 = <(A | B)>x;
const a30 = <A | B>x;
const a31 = <Foo>{ a: 1 };
const a32 = <Foo>[1];
const a33 = <Foo>/regex/;
const a34 = <Foo>1;
const a35 = <Foo>'str';
const a36 = <Foo>class {};
const a37 = <Foo>function () {};
const a38 = <Foo>(async () => {});
const a39 = <Foo>x.y.z();
const a40 = <Foo>foo?.();
const a41 = <Foo>(x satisfies Bar);
const a42 = <Foo>(x instanceof Bar);
const a43 = <Foo>(x < y);
const a44 = <Foo>(x << y);
const a45 = <Foo>(x ** y);
const a46 = < /* c */ Foo /* d */ >x;
const a47 = <Foo>/* c */x;
const a48 = <Foo>(
  x // comment
);
// The parent of the assertion decides the parentheses.
foo(<Foo>x);
foo(<Foo>x, <Bar>y);
foo?.(<Foo>x);
new Bar(<Foo>x);
x + <Foo>y;
x * <Foo>y;
x || <Foo>y;
x && <Foo>y;
x ?? <Foo>y;
x == <Foo>y;
x < <Foo>y;
x | <Foo>y;
x = <Foo>y;
x += <Foo>y;
x ??= <Foo>y;
x = (<Foo>y);
(<Foo>x).y;
(<Foo>x)();
(<Foo>x)[0];
(<Foo>x)!;
new (<Foo>x)();
!<Foo>x;
-<Foo>x;
typeof <Foo>x;
void <Foo>x;
delete (<Foo>x).y;
[<Foo>x];
[...<Foo>x];
({ a: <Foo>x, ...<Bar>y });
foo(...<Foo>x);
`${<Foo>x}`;
foo`${<Foo>x}`;
x ? <Foo>y : <Bar>z;
(<Foo>x, <Bar>y);
if (<Foo>x) {
}
if ((<Foo>x)) {
}
while (<Foo>x) {}
do {} while (<Foo>x);
switch (<Foo>x) {
}
for (const k in <Foo>x) {
}
for (const k of <Foo>x) {
}
async function af() {
  await <Foo>x;
}
function* gf() {
  yield <Foo>x;
}
const arrow = () => <Foo>x;
x[<Foo>y];
x?.[<Foo>y];
function rt() {
  return <Foo>x;
}
function th() {
  throw <Foo>x;
}
<Foo>x;
<Foo>x
const after = 1;
(<Foo>x) as Bar;
<Foo>x as Bar;
const { d1 = <Foo>x } = y;
[x = <Foo>y] = z;
function df(p = <Foo>x) {}
class K {
  p = <Foo>x;
  [<Foo>x]: number;
}
enum E {
  M = <any>1,
}
// Not reported.
const b1 = x as Foo;
const b2 = x as const;
const b3 = { a: 1 } as Foo;
const b4 = [] as Foo[];
export {};
