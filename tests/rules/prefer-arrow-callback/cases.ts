declare function use(...f: unknown[]): void;
declare const a: any;

// Reported.
use(function () {});
use(function (x: number) {
  return x;
});
use(async function () {});
use(function named() {});
use(a || function () {});
use(a ? function () {} : null);
new Promise(function (resolve) {
  resolve(1);
});
use(function () {
  return this;
}.bind(this));
use(function () {
  return 1;
}.bind(a));
use(function (b, b) {});
use(function (this: any) {});

// Not reported.
use(function () {
  return this;
});
use(function* () {});
use(function () {
  return arguments;
});
use(function self(): unknown {
  return self;
});
use(function () {
  return new.target;
});
class B extends Object {
  m() {
    use(function () {
      return super.toString;
    });
  }
}
(function () {})();
const f = function () {};
