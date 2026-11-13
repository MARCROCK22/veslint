// Reported.
class Base {
  value = 1;
  method(): number {
    return this.value;
  }
}
class ThisFirst extends Base {
  constructor() {
    this.value = 2;
    super();
  }
}
class SuperMember extends Base {
  constructor() {
    super.method();
    super();
  }
}
class InArgument extends Base {
  constructor() {
    super(this);
  }
}
class SomePaths extends Base {
  constructor(flag: boolean) {
    if (flag) {
      super();
    }
    this.value = 3;
  }
}
class InCondition extends Base {
  constructor() {
    if (this.value) {
      super();
    } else {
      super();
    }
  }
}
// Not reported.
class Fine extends Base {
  constructor() {
    super();
    this.value = 4;
  }
}
class Arrow extends Base {
  constructor() {
    const later = () => this.value;
    super();
    later();
  }
}
class NotDerived {
  value = 0;
  constructor() {
    this.value = 1;
  }
}
class NullBase extends (null as never) {
  constructor() {
    this.toString();
  }
}
class Parameter extends Base {
  constructor(public readonly x: number) {
    super();
    this.method();
  }
}
export { ThisFirst, SuperMember, InArgument, SomePaths, InCondition, Fine, Arrow, NotDerived, NullBase, Parameter };
