// Reported with the default alias "that".
class A {
  m() {
    const self = this;
    const that = 1;
    let that2;
    return [self, that];
  }
}
function f(this: any) {
  var that;
  that = 1;
}

// Not reported.
function g(this: any) {
  const that = this;
  let other = 1;
  return [that, other];
}
function h(this: any) {
  var that;
  that = this;
}
