// no-unsafe-member-access with noImplicitThis disabled.
function withThis() {
  return [this.a, this.a.b, this['c'], this?.d];
}
class SomeClass {
  x = 1;
  method() {
    return this.x;
  }
}
void withThis;
void SomeClass;
