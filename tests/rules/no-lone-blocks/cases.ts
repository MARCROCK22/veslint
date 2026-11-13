// Reported.
{}
{
  foo();
}
function f() {
  {
    {
      bar();
    }
  }
  {
    var v = 1;
  }
  return v;
}
switch (Math.random()) {
  case 1: {
    foo();
  }
  break;
  default:
    foo();
    {
      bar();
    }
}
class C {
  static {
    {
      foo();
    }
  }
}

// Not reported.
{
  let a = 1;
  foo(a);
}
{
  const b = 1;
  foo(b);
}
{
  class D {}
  foo(D);
}
{
  function g() {}
  g();
}
switch (Math.random()) {
  case 1: {
    foo();
    break;
  }
}
if (Math.random()) {
  foo();
}
label: {
  break label;
}
function foo(..._: unknown[]) {}
function bar() {}
export { f, C };
