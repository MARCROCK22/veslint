declare class Foo {}

// Reported.
new Foo();
(new Foo());
new Foo;

// Not reported.
const a = new Foo();
function f() {
  return new Foo();
}
