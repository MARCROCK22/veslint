/** @deprecated Old function. */
function old(): void {}
function over(a: string): void;
/** @deprecated Number overload. */
function over(a: number): void;
function over(a: unknown): void {
  void a;
}
over!('a');
(over)('a');
(0, over)('a');
old.call(undefined);
void old;

interface Deprecated {
  /** @deprecated Call signature. */
  (): void;
}
declare const table: Record<string, Deprecated>;
declare const keys: { k: string };
table[keys.k]();
declare const callable: Deprecated;
callable();
const tagged = callable;
void tagged;

/** @deprecated Tag function. */
function tag(strings: TemplateStringsArray): string {
  return strings.join('');
}
void tag`text`;

/** @deprecated Decorator. */
function decorate(target: unknown): void {
  void target;
}
/** @deprecated Decorator factory. */
function factory() {
  return (target: unknown) => {
    void target;
  };
}
@decorate
@factory()
class Decorated {}
void Decorated;

interface Chain {
  /** @deprecated Chained method. */
  method(): void;
  nested?: Chain;
}
declare const chain: Chain | undefined;
chain?.method();
(chain?.method)();
chain?.nested?.method();
chain!.method();

class B2 {
  /** @deprecated Base getter only. */
  get x(): number {
    return 1;
  }
  set x(v: number) {
    void v;
  }
}
class D2 extends B2 {
  get x(): number {
    return 2;
  }
  set x(v: number) {
    void v;
  }
}
void new D2().x;

class PB {
  /** @deprecated Base property. */
  pp = 1;
  /** @deprecated Base other. */
  other = 1;
}
class PD extends PB {
  constructor(public pp: number) {
    super();
  }
}
void new PD(1).pp;
class PE extends PB {
  /**
   * @param other The other.
   */
  constructor(public other: number) {
    super();
  }
}
void new PE(1).other;

class TB {
  /** @deprecated Named like a type parameter. */
  T = 1;
}
class TD<T> extends TB {
  value?: T;
}
void TD;

class IB {
  /** @deprecated Inherited doc. */
  m(): void {}
}
class ID extends IB {
  /** @inheritDoc */
  m(): void {}
}
new ID().m();

interface IFace {
  /** @deprecated Interface method. */
  im(): void;
}
class CI implements IFace {
  im(): void {}
}
new CI().im();
interface IE extends IFace {
  im(): void;
}
declare const ie: IE;
ie.im();

class OB {
  /** @deprecated Overridden. */
  om(x: unknown): void {
    void x;
  }
}
class OD extends OB {
  om(x: string): void;
  /** Number. */
  om(x: number): void;
  om(x: unknown): void {
    void x;
  }
}
new OD().om('a');
class OE extends OB {
  om(x: string): void;
  /** @param x Number. */
  om(x: number): void;
  om(x: unknown): void {
    void x;
  }
}
new OE().om('a');
new OE().om(1);

interface UA {
  /** @deprecated In A. */
  m(): void;
}
interface UB {
  m(): void;
}
declare const union: UA | UB;
union.m();
declare const both: UA & UB;
both.m();

function withParam(/** @deprecated Parameter. */ p: number) {
  return p;
}
type FunctionType = (/** @deprecated Function type parameter. */ x: number) => void;
void withParam;
export type { FunctionType };

enum E {
  /** @deprecated First. */
  A = 1,
  B = A,
}
void E;

/** @deprecated Deprecated namespace. */
namespace Dep {
  export const a = 1;
}
namespace Dep.Inner {
  export const b = 1;
}
import Alias = Dep.Inner;
void Alias;

class Base {
  /**
   * @deprecated Use {@link other} or {@link Base.other}.
   */
  method(): void {}
  other(): void {}
}
new Base().method();

/**
 * @deprecated Use {@link p} or {@link T}.
 */
function withLinks<T>(p: T): T {
  return p;
}
withLinks(1);

const literal = {
  /** @deprecated Literal method. */
  method() {},
  /** @deprecated Literal getter. */
  get g() {
    return 1;
  },
};
literal.method();
void literal.g;

declare const shape: { /** @deprecated Same line. */ sameLine: number };
void shape.sameLine;

label: for (;;) {
  break label;
}
