// no-misused-new: a class method named `new` without a body that returns the class, a construct
// signature of an interface that returns the interface, and any method signature named
// `constructor` in an interface or a type literal.
interface I {
  new (): I;
  new (x: string): I;
  new (): J;
  new (): (I);
  new (): I[];
  constructor(): void;
  constructor?(): void;
  get constructor(): string;
  'constructor'(): void;
  ['constructor'](): void;
  [constructor](): void;
}
interface J {}
interface G<T> {
  new <U>(): G<U>;
  new (): G<T>;
}
declare namespace NS {
  interface Inner {
    new (): NS.Inner;
    new (): Inner;
  }
}
type T = {
  new (): T;
  constructor(): void;
};
type U = { constructor: () => void };

class C {
  new(): C;
  new(x: number): C;
  new(x?: number): C | undefined;
  new(y?: string) {}
  static new(): C;
  static new() {}
  'new'(): C;
  ['new'](): C;
  constructor() {}
}

declare abstract class D {
  new(): D;
  new(): C;
  abstract new(): D;
  get new(): D;
}

declare class Generic<T> {
  new(): Generic<T>;
}

const X = class Y {
  new(): Y;
  new() {}
};
const Z = class {
  new(): Z;
  new() {}
};

export default class W {
  new(): W;
  new() {}
}

declare const constructor: unique symbol;
