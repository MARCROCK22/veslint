(function () {
const a = 1;
  const b = 2;
})();
!function () {
const c = 3;
}();
function inner() {
  (function () {
    const d = 4;
  })();
}
