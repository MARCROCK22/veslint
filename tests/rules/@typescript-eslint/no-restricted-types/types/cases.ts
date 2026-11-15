// Reported.
type A = string;
let b: Object;
type C = {};
type D = [];
interface Foo<T> {
  x: T;
}
type E = Foo<string>;
type F = Foo< string >;
type G = Foo<number>;
type Bar = number;
type H = Bar;
declare namespace NS {
  type Baz = number;
}
type I = NS.Baz;
type J = NS. Baz;
interface Qux<X, Y> {}
type K = Qux<A, B>;
type L = Qux<A,/* c */B>;
type M = undefined;
type Ünï = 1;
type N = Ünï;
type O = bigint;
type Callable = () => void;
type P = Callable;
class Impl implements Foo<string>, Bar2 {
  x = '';
}
interface Bar2 {}
interface Ext extends Foo<string>, Object {}
type B = number;
function fn(x: string = ''): Object {
  return x;
}
// Not reported.
type Q = number;
type R = { a: 1 };
type S = [1];
type T = Foo<boolean>;
type U = 'string';
