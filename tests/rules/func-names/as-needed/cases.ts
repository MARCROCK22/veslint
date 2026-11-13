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
