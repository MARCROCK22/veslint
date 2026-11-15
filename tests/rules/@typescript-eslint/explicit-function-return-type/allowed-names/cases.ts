// Not reported: allowed names.
function decl() {}
const allowed = () => 1;
const alsoAllowed = function () {};
const x = function allowed() {};
class C {
  method() {}
  prop = () => 1;
  ['method']() {}
}
const o = { method() {}, prop: () => 1 };
// Reported: other names, computed keys, destructuring.
function other() {}
const notAllowed = () => 1;
const { a = () => 1 } = {} as { a?: () => number };
class D {
  [`prop`] = () => 1;
  other() {}
}
const p = { ['method']: () => 1, 'prop': () => 1 };
