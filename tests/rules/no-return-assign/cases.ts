declare let a: any;

// Reported with "except-parens".
function f1() {
  return a = 1;
}
function f2() {
  return a += 1;
}
const g1 = () => a = 1;
function f3() {
  return a = 1, 2;
}
function f4() {
  return a ? a = 1 : 2;
}

// Not reported.
function f5() {
  return (a = 1);
}
const g2 = () => (a = 1);
function f6() {
  a = 1;
  return a;
}
const g3 = () => {
  a = 1;
};
function f7() {
  return function () {
    a = 1;
  };
}
