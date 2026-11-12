// no-useless-constructor: a constructor without a superclass and with an empty body, or one that
// only calls `super` with its own parameters, is reported (from its start to its parameters) with
// a suggestion that removes it, and leaves a `;` when the next member could continue the member
// before it. Constructors with an accessibility that matters, parameter properties or decorated
// parameters are useful.
declare const B: any, C: any, foo: any, doSomething: any, f: any, Foo: any, Bar: any;
// Cases borrowed from ESLint 10.6.0's tests of the core rule:
class A1 { }
class A2 { constructor(){ doSomething(); } }
class A3 extends B { constructor(){} }
class A4 extends B { constructor(){ super('foo'); } }
class A5 extends B { constructor(foo, bar){ super(foo, bar, 1); } }
class A6 extends B { constructor(){ super(); doSomething(); } }
class A7 extends B { constructor(...args){ super(...args); doSomething(); } }
class A8 { dummyMethod(){ doSomething(); } }
class A9 extends B.C { constructor() { super(foo); } }
class A10 extends B.C { constructor([a, b, c]) { super(...arguments); } }
class A11 extends B.C { constructor(a = f()) { super(...arguments); } }
class A12 extends B { constructor(a, b, c) { super(a, b); } }
class A13 extends B { constructor(foo, bar){ super(foo); } }
class A14 extends B { constructor(test) { super(); } }
class A15 extends B { constructor() { foo; } }
class A16 extends B { constructor(foo, bar) { super(bar); } }
declare class A17 { constructor(options: any); }
class A18 { constructor(){} }
class A19 { constructor     (){} }
class A20 { 'constructor'(){} }
class A21 extends B { constructor() { super(); } }
class A22 extends B { constructor(foo){ super(foo); } }
class A23 extends B { constructor(foo, bar){ super(foo, bar); } }
class A24 extends B { constructor(...args){ super(...args); } }
class A25 extends B.C { constructor() { super(...arguments); } }
class A26 extends B { constructor(a, b, ...c) { super(...arguments); } }
class A27 extends B { constructor(a, b, ...c) { super(a, b, ...c); } }
class A28 {
  foo = 'bar'
  constructor() { }
  [0]() { }
}
class A29 {
  foo = 'bar'
  constructor() { }
  *baz() {}
}
class A30 {
  foo = 'bar'
  constructor() { }
  in
}
class A31 {
  foo = 'bar'
  constructor() { }
  instanceof
}
class A32 {
  foo = 'bar'
  constructor() { }
  #instanceof
}
class A33 {
  foo
  constructor() { }
  [0]() { }
}
class A34 {
  "foo"
  constructor() { }
  [0]() { }
}
class A35 {
  42
  constructor() { }
  [0]() { }
}
class A36 {
  [foo]
  constructor() { }
  [0]() { }
}
class A37 {
  #foo
  constructor() { }
  [0]() { }
}
abstract class A38 { constructor(); }
class A39 { constructor(private name: string) {} }
class A40 { private constructor() {} }
class A41 { protected constructor() {} }
class A42 extends B { public constructor() {} }
class A43 { public constructor() {} }
class A44 extends B { protected constructor(foo, bar) { super(bar); } }
class A45 extends B { public constructor(foo) { super(foo); } }
class A46 { constructor(@Foo foo) {} }
class A47 extends B { constructor(@Foo foo: string) { super(foo); } }
class A48 extends B { constructor(foo: string, @Bar() bar) { super(foo, bar); } }

// More: what the member before the constructor ends with, when the next one starts with `[`.
class S1 {
  x = {}
  constructor() {}
  [0]() {}
}
class S2 {
  x = () => {}
  constructor() {}
  [0]() {}
}
class S3 {
  x = function () {}
  constructor() {}
  [0]() {}
}
class S4 {
  x = class {}
  constructor() {}
  [0]() {}
}
class S5 {
  x = f()
  constructor() {}
  [0]() {}
}
class S6 {
  x = (foo)
  constructor() {}
  [0]() {}
}
class S7 {
  x = `t`
  constructor() {}
  [0]() {}
}
class S8 {
  x = /re/
  constructor() {}
  [0]() {}
}
class S9 {
  x: string
  constructor() {}
  [0]() {}
}
class S10 {
  x = foo as string
  constructor() {}
  [0]() {}
}
class S11 {
  x!: number
  constructor() {}
  [0]() {}
}
class S12 {
  accessor x
  constructor() {}
  [0]() {}
}
class S13 {
  method()
  constructor() {}
  [0]() {}
  method() {}
}
class S14 {
  static {}
  constructor() {}
  [0]() {}
}
class S15 {
  get g() { return 1 }
  constructor() {}
  [0]() {}
}
class S16 {
  x = this
  constructor() {}
  [0]() {}
}
class S17 {
  x = null
  constructor() {}
  [0]() {}
}
class S18 {
  x = true
  constructor() {}
  *[Symbol.iterator]() {}
}
class S19 {
  declare x
  constructor() {}
  [0]() {}
}
class S20 {
  x = [1]
  constructor() {}
  [0]() {}
}
class S21 {
  x?
  constructor() {}
  [0]() {}
}
class S22 {
  x = foo satisfies object
  constructor() {}
  [0]() {}
}
class S23 {
  x = 1n
  constructor() {}
  'str'() {}
}
class S24 {
  x = 1
  constructor() {}
  static [0]() {}
}
class S25 {
  x = foo
  /* a comment */ constructor() {} /* another */
  [0]() {}
}
class S26 extends B {
  constructor(a?: string, b: number) {
    super(a, b);
  }
  [0]() {}
}
class S27 extends B {
  constructor(a, b) {
    super((a), b);
  }
}
class S28 extends B {
  constructor(a, b) {
    super(a, ...b);
  }
}
class S29 extends B {
  constructor(...a) {
    super(...(a));
  }
}
class S30 implements Foo {
  constructor() {}
}
const S31 = class extends B {
  constructor(...args: unknown[]) {
    super(...args);
  }
};
class S32 {
  static constructor() {}
  *constructor() {}
  ['constructor']() {}
}
class S33 extends B {
  readonly x = 1
  constructor() {
    super()
  }
  in() {}
}
