declare let x: any;

// Reported (TypeScript reports them too).
function a() {}
// @ts-expect-error
a = 0;
function b() {
  // @ts-expect-error
  b = 0;
}
const c = function d() {
  // @ts-expect-error
  d = 0;
};
function e() {}
// @ts-expect-error
[e] = x;

// Not reported.
function f(g: any) {
  g = 0;
}
let h = function () {};
h = () => {};
