function generic<T = string>(value?: T): T | undefined {
  return value;
}
class Box<T = number> {
  value?: T;
}
class WithConstructor<T = number> {
  constructor(public value?: T) {}
}
interface Shape<T = string> {
  value: T;
}
interface Pair<T = string, U = number> {
  first: T;
  second: U;
}
interface ArrayDefault<T = string[]> {
  value: T;
}
interface ObjectDefault<T = { a: string }> {
  value: T;
}
interface Previous<T, U = T> {
  first: T;
  second: U;
}
interface Constrained<T extends string = 'a'> {
  value: T;
}
interface NoDefault<T> {
  value: T;
}
type List<T = string> = T[];
type Text = string;
declare function declared<T = number>(value?: T): void;
declare const Constructor: new <T = string>() => object;
namespace NS {
  export interface Inner<T = boolean> {
    value: T;
  }
  export class Klass<T = string> {
    value?: T;
  }
}
import Alias = NS.Inner;
interface Merged<T = string> {
  value: T;
}
declare const Merged: new <T = number>() => Merged<T>;
const object = {
  method<T = string>(value?: T): T | undefined {
    return value;
  },
};

// The last type argument is the default of its type parameter.
generic<string>();
generic<(string)>();
new Box<number>();
new Box<number>;
type A = Shape<string>;
type B = List<string>;
type C = Shape<Text>;
type D = Pair<string, number>;
type E = ArrayDefault<string[]>;
type F = ArrayDefault<Array<string>>;
declared<number>();
new Constructor<string>();
class Implementer implements Shape<string> {
  value = '';
}
interface Extender extends Shape<string> {}
class Child extends Box<number> {}
type G = Generator<number, any, any>;
type H = IterableIterator<string, any, any>;
type J = NS.Inner<boolean>;
type K = Alias<boolean>;
new NS.Klass<string>();
class FromNamespace extends NS.Klass<string> {}
type L = Merged<string>;
new Merged<number>();
object.method<string>();
type M = Constrained<'a'>;
type N = Promise<void>;
type O = Map<string, number>;

// Not the default, or nothing to compare.
type P = Pair<string, boolean>;
type Q = ObjectDefault<{ a: string }>;
type R = Previous<string, string>;
type S = NoDefault<string>;
generic<number>();
new WithConstructor<number>();
const instantiation = generic<string>;
type T = typeof generic<string>;

export type { A, B, C, D, E, F, G, H, J, K, L, M, N, O, P, Q, R, S, T, Extender };
export { Implementer, Child, FromNamespace, instantiation };
