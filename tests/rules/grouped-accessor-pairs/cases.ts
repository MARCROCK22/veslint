// Reported: the getter and the setter of a key are not next to each other.
const a = {
  get x() { return 1; },
  y: 1,
  set x(_: number) {},
};
class B {
  set x(_: number) {}
  m() {}
  get x() { return 1; }
  static get s() { return 1; }
  static t = 1;
  static set s(_: number) {}
  get #p() { return 1; }
  q = 1;
  set #p(_: number) {}
  get ['c' + 'd']() { return 1; }
  r() {}
  set ['c' + 'd'](_: number) {}
  get 'lit'() { return 1; }
  u() {}
  set lit(_: number) {}
}

// Not reported.
const c = {
  get x() { return 1; },
  set x(_: number) {},
  get y() { return 1; },
  get y2() { return 1; },
};
class D {
  get x() { return 1; }
  static set x(_: number) {}
  m() {}
  set y(_: number) {}
  get y() { return 1; }
}
