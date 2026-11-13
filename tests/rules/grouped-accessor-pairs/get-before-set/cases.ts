// Reported with "getBeforeSet".
const a = {
  set x(_: number) {},
  get x() { return 1; },
};
class B {
  static set s(_: number) {}
  static get s() { return 1; }
}

// Not reported.
const c = {
  get x() { return 1; },
  set x(_: number) {},
};
