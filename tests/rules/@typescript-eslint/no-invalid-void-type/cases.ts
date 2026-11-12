// no-invalid-void-type: where `void` may be (a return type, a type argument as the options say, a
// `this` parameter with allowAsThisParameter, a union with never and T<void>, the return type of an
// overloaded implementation) and where it may not (by its parent and grandparent in ESTree).
declare function returns(): void;
declare function parameter(x: void): number;
declare function thisParameter(this: void): number;
declare function rest(...r: void): number;
declare function destructured({ a }: void): number;
declare function optional(x?: void): number;
let variable: void;
let [element]: void = undefined;
const arrow = (): void => {};
const assertion = undefined as void;
const angle = <void>undefined;
type Alias = void;
type Array1 = void[];
type Tuple = [void];
type Function1 = () => void;
type Constructor = new () => void;
type Predicate = (x: unknown) => x is void;
type Mapped<T> = { [K in keyof T]: void };
type Index = { [k: string]: void };
interface Shape {
  property: void;
  method(): void;
  methodParameter(x: void): void;
}
class C<T = void> {
  field: void;
  accessor auto: void = undefined;
  method(): void {}
  get getter(): void {
    return;
  }
}
type Generic = Promise<void>;
type Qualified = Ex.Mx.Tx<void>;
type Defaults<T = void> = T;
type Constrained<T extends void> = T;
type Both<T extends void = void> = T;
type Unions = void | never;
type UnionGeneric = Promise<void> | void;
type UnionOther = void | number;
type UnionParenthesized = (void | number) | never;
type Nested = Array<void | number>;
type Conditional<T> = T extends void ? void : never;
declare function generic<T>(): T;
generic<void>();
declare const Klass: new <T>() => T;
new Klass<void>();
declare class Base<T> {}
interface Iface<T> {}
class Derived extends Base<void> implements Iface<void> {}
interface Child extends Iface<void> {}

// The union in the return type of an overloaded implementation.
function overloaded(): void;
function overloaded(x: number): number;
function overloaded(x?: number): void | number {
  return x;
}
function notOverloaded(x?: number): void | number {
  return x;
}
class Overloads {
  method(): void;
  method(x: number): number;
  method(x?: number): void | number {
    return x;
  }
}

export {};
