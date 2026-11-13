declare function use(f: unknown): void;

// Reported with "always".
use(function () {});
use(async function () {});
use(function* () {});
const a = function () {};
const o = { b: function () {}, ['c']: function () {}, [Symbol.iterator]: function () {} };
class K {
  p = function () {};
  static q = async function () {};
  #r = function () {};
}
export default function () {}

// Not reported.
use(function named() {});
use(() => {});
const m = { n() {}, get g() { return 1; }, set s(_: number) {} };
class L {
  m() {}
}
function decl() {}

// Decorated members, auto-accessors and overloads.
declare function wrap(...a: unknown[]): any;
class Decorated {
  @wrap p = function () {};
  @wrap
  q = function () {};
  @wrap m() {}
  accessor t = function () {};
}
