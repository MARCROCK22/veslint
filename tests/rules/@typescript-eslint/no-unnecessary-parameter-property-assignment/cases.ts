// no-unnecessary-parameter-property-assignment: the constructor assigns a parameter property to
// itself (`this.foo = foo` with `public foo`), unless a field initializer of the class assigns it.
declare const bar: string;
declare const name: string;
declare function run(callback: () => void): void;

class A1 {
  constructor(public foo: string) {
    this.foo = foo;
  }
}
class A2 {
  constructor(private foo?: string, protected baz = '', readonly qux = 1) {
    this.foo = foo!;
    this.baz = baz as any;
    this.qux = (qux);
  }
}
class A3 {
  constructor(public readonly foo: string, public bar: string) {
    this['foo'] = foo;
    this[`bar`] = bar;
  }
}
class A4 {
  constructor(public foo: string, public baz: string, public qux: string) {
    this.foo ||= foo;
    this.baz ??= baz;
    this.qux &&= qux;
  }
}
class A5 {
  constructor(private foo: string) {
    (this.foo) = foo;
    (() => {
      this.foo = foo;
    })();
    run(() => {
      this.foo = foo;
    });
  }
}
class A6 {
  constructor(private foo: string) {
    class Inner {
      constructor(private foo: string) {
        this.foo = foo;
      }
    }
    this.foo = foo;
    void Inner;
  }
}
const A7 = class {
  constructor(public foo: string) {
    const copy = foo;
    this.foo = foo;
    void copy;
  }
};
class A8 {
  'constructor'(public foo: string) {
    this.foo = foo;
  }
}
class A9 {
  other = 1;
  constructor(public foo: string) {
    this.bar += 'x';
    this.foo = foo;
  }
  bar = '';
}
class A10 {
  constructor(public foo: string) {
    this.foo = foo;
  }
  arrow = () => {
    this.foo = 'arrow';
  };
  accessor field = (this.foo = 'accessor');
}
class B0 {}
class A11 extends B0 {
  constructor(override foo: string) {
    super();
    this.foo = foo;
  }
  foo2 = '';
}
function a12() {
  // Inside a function, findParentFunction finds it from the field initializer too.
  class Local {
    constructor(public foo: string) {
      this.foo = foo;
    }
    init = (this.foo = 'init');
  }
  return Local;
}

// Not reported.
class B1 {
  constructor(foo: string) {
    this.foo = foo;
  }
  foo: string;
}
class B2 {
  constructor(private foo: string) {
    this.foo = bar;
    this.foo = foo.length.toString();
    this.foo = this.baz;
    this.foo = foo satisfies string;
    this.foo = <string>foo;
  }
  baz = '';
}
class B3 {
  constructor(private foo: string) {
    this.bar = () => {
      this.foo = foo;
    };
    function inner(this: B3) {
      this.foo = foo;
    }
    void inner;
  }
  bar = () => {};
}
class B4 {
  constructor(private foo: string) {
    this[`${foo}`] = foo;
    this[name] = foo;
    B4.foo = foo;
    this.#secret = foo;
  }
  static foo = '';
  #secret = '';
  [key: string]: unknown;
}
class B5 {
  constructor(public foo: number) {
    this.foo += foo;
    this.foo -= foo;
    this.foo += 1;
    this.foo = foo;
  }
}
class B6 {
  constructor(public foo: number, cond: boolean) {
    if (cond) {
      this.foo *= 2;
    } else {
      this.foo = foo;
    }
  }
}
class B7 {
  constructor(public foo: number) {
    this.foo = foo;
  }
  init = (this.foo += 1);
}
class B8 {
  constructor(public foo: number) {
    this.foo = foo;
  }
  init = (() => {
    this.foo += 1;
  })();
}
class B9 {
  constructor(public foo: number) {
    {
      const foo = 1;
      this.foo = foo;
    }
  }
}
class B10 {
  static constructor(foo: string) {
    this.foo = foo;
  }
  static foo = '';
}
const b11 = {
  constructor(this: { foo: string }, foo: string) {
    this.foo = foo;
  },
};
function B12(this: { foo: string }, foo: string) {
  this.foo = foo;
}
class B13 {
  constructor(public foo: number) {
    this.foo = foo;
  }
  static {
    this.prototype.foo = 1;
  }
  init2 = ((this.foo)) = 2;
}

export { A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, a12, B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, b11, B12, B13 };
