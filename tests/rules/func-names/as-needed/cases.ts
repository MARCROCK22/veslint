declare function use(f: unknown): void;
let x: unknown;

// Reported with "as-needed".
use(function () {});
(function () {})();
const arr = [function () {}];

// Not reported: the function gets a name.
const a = function () {};
const o = { b: function () {} };
class K {
  p = function () {};
}
x = function () {};
function f(y = function () {}) {}
const { z = function () {} } = {} as any;

// No inferred name: a key `__proto__`, a parenthesized target, an operator other than `=`, `&&=`,
// `||=` and `??=` (10.15.0).
let target: any;
const proto1 = { __proto__: function () {} };
const proto2 = { '__proto__': function () {} };
const proto3 = { ['__proto__']: function () {} };
(target) = function () {};
target += function () {};
target &&= function () {};
target ||= function () {};
target ??= function () {};
[(target) = function () {}] = [];
[target = function () {}] = [];
({ target = function () {} } = {});
