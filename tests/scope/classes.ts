// ClassVisitor.
declare function dec(...args: any[]): any;
declare const key: 'k';
declare const sym: unique symbol;
interface I1 { a: number }
interface I2<T> { b: T }
class Base<T = number> { constructor(public bp: T) {} }
@dec
class C<T extends object, U = T> extends Base<T> implements I1, I2<U> {
  a = 1;
  static s: number = C.length;
  declare d: string;
  readonly r?: T;
  [key] = key;
  [sym]: U | undefined;
  #priv = this.a;
  accessor acc: number = 2;
  static accessor sacc = 3;
  @dec prop: I1 | undefined;
  @dec('x', key) accessor decorated = 1;
  b: T;
  static { const inStatic = C; inStatic; }
  static { let again = 1; again++; }
  constructor(private pp: T, protected readonly pr = pp, @dec public dp?: U, ...rest: number[]) {
    super(pp);
    this.b = pp;
    rest;
  }
  method<M>(@dec mp: M, mq = mp): M { return mq; }
  @dec decoratedMethod(@dec() @dec x: number) { return x; }
  [key + 'c'](c1: number) { return c1; }
  get g(): T { return this.b; }
  set g(value: T) { this.b = value; }
  static sm() { return C; }
  async am() {}
  *gm() {}
  #pm() { return this.#priv; }
  overload(a: string): void;
  overload(a: number): void;
  overload(a: any): void { a; }
  arrowField = (af: T) => af;
  fnField = function fnName(ff: U) { return fnName; };
  classField = class Inner { x = Inner; };
  [index: string]: unknown;
}
abstract class Abs<A> {
  abstract ap: A;
  abstract am(x: A): void;
  abstract get ag(): A;
  abstract accessor aacc: A;
  protected abstract [key]: number;
  concrete(p: A) { return p; }
}
const Expr = class Named<E> extends C<object> { m(e: E) { return [Named, e]; } };
const Anon = class { static x = Anon; };
export default class extends Abs<number> { ap = 1; am() {} get ag() { return 1; } accessor aacc = 1; [key] = 1; }
export { C, Expr };
@dec export class Exported {}
export @dec class Exported2 {}
class Shadow { Shadow = 1; m(Shadow: number) { return Shadow; } }
new Shadow();
class Heritage extends (dec(Base) as typeof Base)<string> implements NsI.Deep<I1> {}
declare namespace NsI { interface Deep<T> { t: T } }
new Heritage('x');
