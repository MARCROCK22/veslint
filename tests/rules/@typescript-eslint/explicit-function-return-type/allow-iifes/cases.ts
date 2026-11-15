// Not reported: IIFEs.
(function () {})();
(() => 1)();
const r = (() => {
  return 1;
})();
// Reported.
const f = () => 1;
function g() {}
(function () {}).call(null);
