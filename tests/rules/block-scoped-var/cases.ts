declare const x: boolean;

// Reported.
function f1() {
  if (x) {
    var a = 1;
  }
  return a;
}
function f2() {
  for (var i = 0; i < 1; i++) {}
  return i;
}
function f3() {
  try {
    var b = 1;
  } catch (e) {
    b = 2;
  }
}
function f4() {
  switch (x) {
    case true:
      var c = 1;
  }
  return c;
}

// Not reported.
function g() {
  var d = 1;
  if (x) {
    d = 2;
  }
  return d;
}
