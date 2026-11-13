// Reported.
class A {
  static {}
}
class B {
  static {

  }
}
const C = class {
  static {}
  static {
  }
};

// Not reported.
class D {
  static {
    // comment
  }
  static { /* inline */ }
  static {
    ;
  }
  static {
    D.x = 1;
  }
  static x: number;
}

// Comments around the block: only those between its braces count.
class E {
  static /* before */ {} /* after */
}
