declare let a: any;

// Reported with "always".
function f1() {
  return (a = 1);
}
const g = () => (a = 1);

// Not reported.
function f2() {
  a = 1;
}
