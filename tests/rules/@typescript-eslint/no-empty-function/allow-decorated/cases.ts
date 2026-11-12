// no-empty-function: a function, method, getter, setter or constructor whose body has no
// statements nor comments, reported at its body with a suggestion that adds a comment.
// Cases borrowed from ESLint 10.6.0's tests of the core rule (each item of its tests once):
function foo() {}
var foo = function() {};
var obj = {foo: function() {}};
var foo = () => {};
function* foo() {}
var foo = function*() {};
var obj = {foo: function*() {}};
var obj = {foo() {}};
class A {foo() {}}
class A {static foo() {}}
var A = class {foo() {}};
var A = class {static foo() {}};
var obj = {*foo() {}};
class A {*foo() {}}
class A {static *foo() {}}
var A = class {*foo() {}};
var A = class {static *foo() {}};
var obj = {get foo() {}};
class A {get foo() {}}
class A {static get foo() {}}
var A = class {get foo() {}};
var A = class {static get foo() {}};
var obj = {set foo(value) {}};
class A {set foo(value) {}}
class A {static set foo(value) {}}
var A = class {set foo(value) {}};
var A = class {static set foo(value) {}};
class A {constructor() {}}
var A = class {constructor() {}};
const foo = { async method() {} }
async function a(){}
const foo = async function () {}
class Foo { async bar() {} }
const foo = async () => {};
var foo = () => 0;
var foo = function () {
}
var foo = () => { 

  }
var obj = {
	foo() {
	}
}
class A { foo() { } }
const foo = function(param: string) {};
const obj = {foo: function(param: string) {}};
const foo = (param: string) => {};
function* foo(param: string) {}
const foo = function*(param: string) {};
const obj = {foo: function*(param: string) {}};
const obj = {foo(param: string) {}};
class A { foo(param: string) {} }
class A { private foo() {} }
class A { protected foo() {} }
class A { static foo(param: string) {} }
class A { private static foo() {} }
class A { protected static foo() {} }
const A = class {foo(param: string) {}};
const A = class {static foo(param: string) {}};
const A = class {private static foo() {}};
const A = class {protected static foo() {}};
class B { @decorator() foo() {} }
const B = class { @decorator() foo() {} }
class B extends C { override foo() {} }
class B extends C { @decorator() override foo() {} }
const obj = {*foo(param: string) {}};
class A { *foo(param: string) {} }
class A {static *foo(param: string) {}}
class A {private static *foo() {}}
class A {protected static *foo() {}}
const A = class {*foo(param: string) {}};
const A = class {static *foo(param: string) {}};
const obj = {get foo(): string {}};
class A {get foo(): string {}}
class A {static get foo(): string {}}
const A = class {get foo(): string {}};
const A = class {static get foo(): string {}};
class A {@decorator() get foo(): string {}}
class A {@decorator() static get foo(): string {}}
const A = class {@decorator() get foo(): string {}};
const A = class {@decorator() static get foo(): string {}};
class A extends B {override get foo(): string {}}
class A extends B {static override get foo(): string {}}
const A = class extends B {override get foo(): string {}};
const A = class extends B {static override get foo(): string {}};
const obj = {set foo(value: string) {}};
class A {set foo(value: string) {}}
class A {static set foo(value: string) {}}
const A = class {set foo(value: string) {}};
const A = class {static set foo(value: string) {}};
class A {@decorator() set foo(value: string) {}}
class A {@decorator() static set foo(value: string) {}}
const A = class {@decorator() set foo(value: string) {}};
const A = class {@decorator() static set foo(value: string) {}};
class A extends B {override set foo(value: string) {}}
class A extends B {static override set foo(value: string) {}}
const A = class extends B {override set foo(value: string) {}};
const A = class extends B {static override set foo(value: string) {}};
class A { constructor(param: string) {} }
class B { private constructor() {} }
class B { protected constructor() {} }
const A = class {constructor(param: string) {}};
const B = class { private constructor() {} }
const B = class { protected constructor() {} }
const foo = { async method(param: string) {} }
async function a(param: string){}
const foo = async function(param: string) {}
class A { async foo(param: string) {} }
class A { @decorator() async foo(param: string) {} }
class A extends B { override async foo(param: string) {} }
const foo = async (): Promise<void> => {};
class A { private constructor() {} }
const A = class { private constructor() {} };
class A { protected constructor() {} }
const A = class { protected constructor() {} };
class A { @decorator() foo() {} }
const A = class { @decorator() foo() {} }
class B {@decorator() get foo(): string {}}
class B {@decorator() static get foo(): string {}}
const B = class {@decorator() get foo(): string {}};
const B = class {@decorator() static get foo(): string {}};
class B {@decorator() set foo(value: string) {}}
class B {@decorator() static set foo(value: string) {}}
const B = class {@decorator() set foo(value: string) {}};
const B = class {@decorator() static set foo(value: string) {}};
class B { @decorator() async foo(param: string) {} }
class A extends B { @decorator() override foo() {} }
class B extends C {override get foo(): string {}}
class B extends C {static override get foo(): string {}}
const B = class extends C {override get foo(): string {}};
const B = class extends C {static override get foo(): string {}};
class B extends C {override set foo(value: string) {}}
class B extends C {static override set foo(value: string) {}}
const B = class extends C {override set foo(value: string) {}};
const B = class extends C {static override set foo(value: string) {}};
class B extends C { override async foo(param: string) {} }
class C extends D { @decorator() override foo() {} }
class A extends B { override foo() {} }
class A { constructor(public param: string) {} }
class A { constructor(private param: string) {} }
class A { constructor(protected param: string) {} }
class A { constructor(readonly param: string) {} }

// More: names of the functions, things that are not empty, and what typescript-estree does.
declare function dec(...args: unknown[]): any;
declare class Base { method(): void; }
class Names extends Base {
  #priv() {}
  static #spriv() {}
  static async *gen() {}
  '#str'() {}
  [Symbol.iterator]() {}
  ['computed']() {}
  0x10n() {}
  1e1() {}
  '\u{1F600}'() {}
  '😀'(): void {}
  accessor acc = () => {};
  accessor acc2 = function () {};
  field = function named() {};
  static arrow = async () => {};
  #privField = () => {};
  @dec decorated() {}
  @dec
  // between
  decorated2() {}
  override method() {}
  overload(a: string): void;
  overload(a?: string) {}
  withComment() { /* c */ }
  withLineComment() {
    // c
  }
  withEmptyStatement() { ; }
  constructor(public readonly x: string) { super(); }
}
abstract class AbstractField {
  abstract x: () => void;
}
const objectMethods = {
  get a() {},
  set a(v) {},
  async *b() {},
  c: async function* () {},
  'd e'() {},
  [`tmpl`]() {},
};
export default function () {}
const arrowWithType = (): void => {};
const expressionBody = () => 0;
function outer() {
  function inner() {}
  return () => {};
}
class OnlyParameterProperty {
  constructor(private a: string) {}
}
class OverrideParameterProperty extends Base {
  constructor(override readonly b: string) {
    super();
  }
}
class ConstructorOverloads {
  constructor(a: string);
  constructor(a?: string) {}
  static constructor() {}
  'constructor'() {}
}

// A comment after the `}` of a body without `;`, which tree-sitter puts in the block.
class TrailingComments {
  method() {} // comment
  field = () => {} // comment
}
const trailing = async () => {} /* block comment */
// Methods named `constructor` that are not constructors.
class NotConstructors {
  *constructor() {}
  get constructor() {}
}
