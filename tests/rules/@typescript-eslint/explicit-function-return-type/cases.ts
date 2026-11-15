// Reported: declarations, expressions, methods, accessors.
function noType() {
  return 1;
}
export function exported(a: number) {
  return a;
}
const arrow = () => 1;
const fnExpr = function () {
  return 'x';
};
const named = function inner() {};
class K {
  method() {}
  static staticMethod() {}
  get getter() {
    return 1;
  }
  set setter(v: number) {}
  constructor() {}
  prop = () => 1;
  #priv() {}
  async asyncMethod() {}
  *gen() {}
  ['computed' + 1]() {}
  'quoted'() {}
}
function decorator(..._args: unknown[]): void {}
class D {
  @decorator
  decorated() {}
  @decorator @decorator
  twoDecorators<T>(x: T) {
    return x;
  }
  @decorator
  arrowProp = (x: number) => x;
}
const obj = {
  method() {},
  prop: function () {},
  arrow: () => {},
  get g() {
    return 1;
  },
  async *asyncGen() {},
};
const single = x => x;
const parens = (x: number) => x;
const generic = <T,>(x: T) => x;
const ünïcode = (é: string) => é;
export default function () {}
(function () {})();
(() => {})();
[1].map(x => x);
setTimeout(function () {});

// Not reported: typed, higher order, const assertions, typed contexts.
function typed(): number {
  return 1;
}
const typedArrow = (): void => {};
const higher = () => () => 1;
function higherDecl() {
  return function (): void {};
}
const higherTwo = () => {
  return (): number => 1;
};
const constAssert = () => ({ a: 1 }) as const;
const constSatisfies = () => ({ a: 1 }) as const satisfies object;
const angle = () => <const>{ a: 1 };
type Fn = () => number;
const typedVar: Fn = () => 1;
const asserted = (() => 1) as Fn;
const objTyped: { f: Fn } = { f: () => 1 };
const nested: { o: { f: Fn } } = { o: { f: () => 1 } };
const objAs = { f: () => 1 } as { f: Fn };
class Typed {
  p: Fn = () => 1;
}
function defaultParam(f: Fn = () => 1): void {}
new Promise(resolve => resolve(1));
function returnsTyped(): Fn {
  return () => 1;
}
const returnsTypedArrow = (): Fn => () => 1;
function wrapper(): { f: Fn } {
  return { f: () => 1 };
}
declare function declared(): void;
