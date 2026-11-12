// no-dupe-class-members: a class member whose static name was already declared in the same class,
// static or not, as a method or field (a getter and a setter may share it). Computed keys, private
// names, constructors, overloads, abstract members and accessor properties are not looked at.
// Cases borrowed from ESLint 10.6.0's tests of the core rule, one class per line:
class A1 { foo() {} bar() {} }
class A2 { static foo() {} foo() {} }
class A3 { get foo() {} set foo(value) {} }
class A4 { static foo() {} get foo() {} set foo(value) {} }
class A5 { foo() { } } class B5 { foo() { } }
class A6 { [foo]() {} foo() {} }
class A7 { 'foo'() {} 'bar'() {} baz() {} }
class A8 { *'foo'() {} *'bar'() {} *baz() {} }
class A9 { get 'foo'() {} get 'bar'() {} get baz() {} }
class A10 { 1() {} 2() {} }
class A11 { ['foo']() {} ['bar']() {} }
class A12 { [`foo`]() {} [`bar`]() {} }
class A13 { [12]() {} [123]() {} }
class A14 { [1.0]() {} ['1.0']() {} }
class A15 { [0x1]() {} [`0x1`]() {} }
class A16 { [null]() {} ['']() {} }
class A17 { get ['foo']() {} set ['foo'](value) {} }
class A18 { ['foo']() {} static ['foo']() {} }
class A19 { ['constructor']() {} constructor() {} }
class A20 { 'constructor'() {} [`constructor`]() {} }
class A21 { constructor() {} get [`constructor`]() {} }
class A22 { 'constructor'() {} set ['constructor'](value) {} }
class A23 { ['foo' + '']() {} ['foo']() {} }
class A24 { [`foo${''}`]() {} [`foo`]() {} }
class A25 { [-1]() {} ['-1']() {} }
class A26 { [foo]() {} [foo]() {} }
class A27 { foo; static foo; }
class A28 { foo; #foo; }
class A29 { '#foo'; #foo; }
class A30 { foo() {} foo() {} }
!class A31 { foo() {} foo() {} };
class A32 { 'foo'() {} 'foo'() {} }
class A33 { 10() {} 1e1() {} }
class A34 { ['foo']() {} ['foo']() {} }
class A35 { static ['foo']() {} static foo() {} }
class A36 { set 'foo'(value) {} set ['foo'](val) {} }
class A37 { ''() {} ['']() {} }
class A38 { [`foo`]() {} [`foo`]() {} }
class A39 { static get [`foo`]() {} static get ['foo']() {} }
class A40 { foo() {} [`foo`]() {} }
class A41 { get [`foo`]() {} 'foo'() {} }
class A42 { static 'foo'() {} static [`foo`]() {} }
class A43 { ['constructor']() {} ['constructor']() {} }
class A44 { static [`constructor`]() {} static constructor() {} }
class A45 { static constructor() {} static 'constructor'() {} }
class A46 { [123]() {} [123]() {} }
class A47 { [0x10]() {} 16() {} }
class A48 { [100]() {} [1e2]() {} }
class A49 { [123.00]() {} [`123`]() {} }
class A50 { static '65'() {} static [0o101]() {} }
class A51 { [123n]() {} 123() {} }
class A52 { [null]() {} 'null'() {} }
class A53 { foo() {} foo() {} foo() {} }
class A54 { static foo() {} static foo() {} }
class A55 { foo() {} get foo() {} }
class A56 { set foo(value) {} foo() {} }
class A57 { foo; foo; }
declare const foo: string;

// More: fields, `declare`, getters and setters, escapes, numbers, BigInts.
class B1 {
  declare x: number;
  x = 1;
  get y() { return 1; }
  get y() { return 2; }
  set y(value: number) {}
  set y(value: number) {}
  static y = 1;
  'f\x6fo'() {}
  foo() {}
  0x10n() {}
  16() {}
  1_000() {}
  '1000'() {}
  .5() {}
  '0.5'() {}
  #bar() {}
  bar = 1;
}
class B2 {
  overload(a: string): void;
  overload(a: number): void;
  overload(a: unknown) {}
  overload() {}
  constructor(a: string);
  constructor(a?: string) {}
  static constructor() {}
  static constructor() {}
  accessor acc = 1;
  acc() {}
  optional?() {}
  optional?() {}
}
abstract class B3 {
  abstract foo(): void;
  foo() {}
  abstract bar: number;
  bar = 1;
  bar = 2;
}
const B4 = class {
  inner = class {
    foo() {}
    foo() {}
  };
  foo() {}
};
declare class B5 {
  foo(): void;
  foo(): void;
  bar: number;
  bar: number;
}
