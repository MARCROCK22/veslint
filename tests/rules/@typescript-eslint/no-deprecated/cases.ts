import { stale, fresh, oldValue, value, OldClass, Ctor, aliasedLocal, plainAlias, OldNs } from './other';
import type { Shape } from './other';
import def from './other';
import * as ns from './other';
import { staleAgain, freshDeprecatedAlias } from './reexport';

stale();
fresh();
void oldValue;
void value;
new OldClass();
new Ctor();
new Ctor(1);
void aliasedLocal;
void plainAlias;
void def;
ns.stale();
void ns.oldValue;
void OldNs.inner;
staleAgain();
freshDeprecatedAlias();

declare const shape: Shape;
shape.area();
shape.area2();
void shape.prop;
shape.fnProp();
shape.deprecatedFnProp();
const { prop } = shape;
const { prop: renamedProp } = shape;
void shape['prop'];
const key = 'prop' as const;
void shape[key];
void [prop, renamedProp];

/** @deprecated Local function. */
function localOld(): void {}
localOld();
const alias = localOld;
/** @deprecated */
let counter = 1;
counter = 2;
counter++;
const shorthand = { counter };
const longhand = { a: counter };
const arrowBody = () => counter;
const arrowBlock = () => {
  return counter;
};
function withDefault(p = counter) {
  return p;
}
void [alias, shorthand, longhand, arrowBody, arrowBlock, withDefault];

class Base {
  /** @deprecated Base method. */
  m(): void {}
  /** @deprecated Static base. */
  static s(): void {}
  /** @deprecated Base field. */
  field = 1;
  /** @deprecated Base getter. */
  get acc(): number {
    return 1;
  }
}
class Derived extends Base {
  m(): void {}
  static s(): void {}
  field = 2;
  get acc(): number {
    return 2;
  }
  call() {
    this.m();
    Derived.s();
    void this.field;
    void this.acc;
    super.m();
  }
}
new Derived().m();
Derived.s();

function over(a: string): void;
/** @deprecated Number overload. */
function over(a: number): void;
function over(a: unknown): void {
  void a;
}
over('a');
over(1);
const overAlias = over;
void overAlias;

/** @deprecated Use {@link fresh} or {@link fresh | the fresh one} or {@linkcode fresh text}. */
function linked(): void {}
linked();
/** @deprecated See {@link Nope} and {@link https://example.com | docs} or {@link https://example.com}. */
function linked2(): void {}
linked2();
/** @deprecated {@link Base#m} member and {@link Base.s} static and {@link Nope.deep}. */
function linked3(): void {}
linked3();
/** @deprecated {@linkplain fresh}{@link fresh()} {@link Base<number> generic} {@link} */
function linked4(): void {}
linked4();
/**
 * @deprecated Use {@link
 * fresh} across lines, {@link fresh
 * and more}.
 */
function linked5(): void {}
linked5();
function overLinked(a: string): void;
/** @deprecated Use {@link fresh | Fresh}. */
function overLinked(a: number): void;
function overLinked(a: unknown): void {
  void a;
}
overLinked(1);

/** @deprecated Old base class. */
class OldBase {}
class Child extends OldBase {
  constructor() {
    super();
  }
  /** @deprecated Private field. */
  #p = 1;
  /** @deprecated Private method. */
  #pm() {}
  use() {
    void this.#p;
    this.#pm();
    return #p in this;
  }
}
void Child;

/** @deprecated Old type. */
type OldType = string;
const typed: OldType = '';
/** @deprecated Old interface. */
interface OldIface {}
class Impl implements OldIface {}
function generic<T extends OldType>(t: T): T {
  return t;
}
type Query = typeof localOld;
void [typed, Impl, generic];
export type { Query };

enum Color {
  /** @deprecated Use Blue. */
  Red,
  Blue,
}
void Color.Red;
void Color['Red'];
void Color.Blue;

abstract class Abstract {
  /** @deprecated Abstract method. */
  abstract am(): void;
  /** @deprecated Abstract property. */
  abstract ap: number;
}
void Abstract;

export { localOld };
export { localOld as renamedOld };
export {
  /** @deprecated The export is deprecated. */
  fresh as freshAlias,
};

/** @deprecated Old with new.target. */
class WithNewTarget {
  constructor() {
    void new.target;
  }
}
void WithNewTarget;

/** @deprecated Statement doc. */
const firstDeclarator = 1,
  secondDeclarator = () => {};
secondDeclarator();
void secondDeclarator;
void firstDeclarator;

const initArrow = /** @deprecated Initializer arrow. */ () => {};
initArrow();
void initArrow;
const objectInit = {
  /** @deprecated Outer. */
  p2: /** @deprecated Inner. */ () => {},
};
objectInit.p2();

void 'abc'.substr(1);

class Accessors {
  /** @deprecated Getter. */
  get v(): number {
    return 1;
  }
  set v(x: number) {
    void x;
  }
}
const accessors = new Accessors();
void accessors.v;
accessors.v = 1;
