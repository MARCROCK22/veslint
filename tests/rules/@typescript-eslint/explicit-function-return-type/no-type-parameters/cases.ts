// Not reported: no type parameters.
function a() {}
const b = () => 1;
class C {
  m() {}
}
// Reported: type parameters.
function d<T>(x: T) {
  return x;
}
const e = <T,>(x: T) => x;
class F {
  m<T>(x: T) {
    return x;
  }
}
