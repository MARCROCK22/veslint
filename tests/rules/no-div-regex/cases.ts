// Reported and fixed.
function f() {
  return /=foo/;
}
// Not reported.
const ok = /[=]foo/;
const ratio = 4 / 2;
export { f, ok, ratio };
