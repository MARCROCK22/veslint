// A generator or an accessor named `constructor` is not the constructor; a quoted name is.
class A {
  *constructor() {}
  get constructor() { return 1; }
}
class B {
  'constructor'() {}
  async *Constructor() {}
}
class C {
  static constructor() {}
  async *constructor() {}
}
// U+2028 and U+2029 in the pattern are written as escapes in the message, as V8 does.
export const fooBar = 1;
export { A, B, C };
