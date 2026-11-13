// Reported.
class Base {
  constructor(public x = 0) {}
}
class MissingAll extends Base {
  constructor() {
    console.log('no super');
  }
}
class MissingSome extends Base {
  constructor(flag: boolean) {
    if (flag) {
      super();
    }
  }
}
class Duplicate extends Base {
  constructor() {
    super();
    super(1);
  }
}
class InLoop extends Base {
  constructor(n: number) {
    for (let i = 0; i < n; i++) {
      super();
    }
  }
}
class NotConstructor extends (null as unknown as typeof Base) {}
class BadSuper extends (1 as never) {
  constructor() {
    super();
  }
}
class Plain {
  constructor() {
    super();
  }
}
// Not reported.
class Fine extends Base {
  declare y: number;
  constructor() {
    super(2);
  }
}
class Branches extends Base {
  constructor(flag: boolean) {
    if (flag) {
      super(1);
    } else {
      super(2);
    }
  }
}
class Returns extends Base {
  constructor() {
    return Object.create(Base.prototype);
  }
}
class Overloaded extends Base {
  constructor();
  constructor(x: number);
  constructor(x?: number) {
    super(x);
  }
}
class Mixin extends (Math.random() ? Base : class {}) {
  constructor() {
    super();
  }
}
class NoConstructor extends Base {}
export { MissingAll, MissingSome, Duplicate, InLoop, NotConstructor, BadSuper, Plain, Fine, Branches, Returns, Overloaded, Mixin, NoConstructor };
