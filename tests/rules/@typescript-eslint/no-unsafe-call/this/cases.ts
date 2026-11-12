// no-unsafe-call with noImplicitThis disabled: `this` is `any` in standalone functions.
function withThis() {
  this();
  this.method();
  this.a.b();
  this?.method();
}
class SomeClass {
  method() {
    this.other();
  }
  other() {}
}
void withThis;
void SomeClass;
