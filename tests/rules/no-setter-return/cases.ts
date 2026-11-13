// Reported.
class A {
  set x(v: number) {
    return v;
  }
  static set y(v: number) {
    if (v) {
      return v + 1;
    }
  }
}
const o = {
  set z(v: number) {
    return v;
  },
};
Object.defineProperty(o, 'p', {
  set(v: number) {
    return v;
  },
});
Reflect.defineProperty(o, 'q', {
  set: function (v: number) {
    return v;
  },
});
Object.defineProperties(o, {
  r: {
    set: (v: number) => v,
  },
});
Object.create(null, {
  s: {
    set(v: number) {
      return v;
    },
  },
});

// Not reported.
class B {
  set x(v: number) {
    return;
  }
  set y(v: number) {
    const f = () => {
      return v;
    };
    function g() {
      return v;
    }
  }
  get z() {
    return 1;
  }
}
const p = {
  set(v: number) {
    return v;
  },
};
foo.defineProperty(o, 'x', {
  set(v: number) {
    return v;
  },
});
declare const foo: any;
function shadow(Object: any) {
  Object.defineProperty(o, 'x', {
    set(v: number) {
      return v;
    },
  });
}
