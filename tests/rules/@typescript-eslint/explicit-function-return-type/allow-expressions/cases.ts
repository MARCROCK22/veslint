// Reported: declarations and functions assigned or exported.
function decl() {}
const assigned = () => 1;
export default () => {};
class C {
  method() {}
  prop = () => 1;
}
// Not reported: expressions.
[1].map(x => x);
(function () {})();
(() => {})();
const o = { m() {}, f: () => 1 };
foo(function () {});
declare function foo(f: unknown): void;
