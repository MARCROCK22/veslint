declare function g(): void;

// Reported.
function* a() {
  g();
}
const b = function* () {
  g();
};
class C {
  *m() {
    g();
  }
  static *s() {
    return 1;
  }
}
const o = {
  *m() {
    g();
  },
};
function* d() {
  function* inner() {
    yield 1;
  }
}

// Not reported.
function* e() {}
function* f() {
  yield;
}
function* h() {
  const x = yield* f();
  return x;
}
function k() {
  g();
}
function* l() {
  // only a comment
}
