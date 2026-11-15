declare function Decorator(): any;
declare function compute(value: unknown): number;
declare function later(callback: () => unknown): void;
// Reported and fixed: the members by their groups, then by name.
export class Members {
  method() {}
  b = 1;
  a = 2;
  constructor() {}
  static staticMethod() {}
  protected protectedProperty = 3;
  private privateProperty = 4;
  static staticProperty = 5;
  [key: string]: unknown;
  static {
    compute(1);
  }
  get getter() {
    return 1;
  }
  set setter(value: number) {}
  #secret = 6;
  accessor auto = 7;
  arrow = () => 8;
  private privateMethod() {}
  protected protectedMethod() {}
}
// The comments above and after the members move with them.
class Comments {
  // About b.
  b = 1; // After b.
  /* About a. */
  a = 2;
}
// A member that uses another one comes after it.
class Dependencies {
  a = this.c + 1;
  b = 2;
  c = 3;
  d = Dependencies.e;
  static e = 1;
}
class StaticDependencies {
  static b = StaticDependencies.c;
  static a = 1;
  static c = 2;
  static d = this.a;
}
// Inside a function that is not called right away, it is not a dependency.
class Deferred {
  b = () => this.c;
  a = later(() => this.c);
  c = 1;
}
class Cycle {
  b = this.a;
  a = this.b;
}
class Wrong {
  c = this.a;
  a = 1;
  b = 2;
}
// Overload signatures stay with their implementation.
class Overloads {
  b(): void;
  b(value: number): void;
  b(value?: number) {}
  a() {}
}
abstract class Abstract {
  abstract b(): void;
  abstract a: number;
  protected abstract c(): void;
  private d = 1;
}
class Decorated {
  @Decorator() b = 1;
  @Decorator()
  a = 2;
  c = 0;
}
class Private {
  #b = 1;
  #a = this.#b;
  c = 2;
}
declare class Declared {
  b(): void
  a(): void
}
class Semicolons {
  b = 1
  a = 2
  ['c'] = 3
}
class Quoted {
  'b' = 1;
  'a' = 2;
  [`c`] = 3;
  1 = 4;
}
const expression = class Named {
  b = 1;
  a = Named.c;
  static c = 1;
};
// eslint-disable comments keep a member in place.
class Disabled {
  c = 1;
  b = 2;
  a = 3; // eslint-disable-line
}
class Optional {
  b?: number;
  a?(): void;
  readonly d = 1;
  declare c: number;
  override toString() {
    return '';
  }
  async e() {}
}
// Not reported.
class Sorted {
  static a = 1;
  b = 2;
  c = 3;
  constructor() {}
  d() {}
}
class Single {
  a = 1;
}
class Empty {}
