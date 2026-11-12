// no-unnecessary-type-parameters: type parameters that are used only once.
declare function mapIt<M>(value: M): { [K in keyof M]: M[K] };
declare function boxIt<B>(value: B): { value: B };
interface Shape {
  kind: string;
}

function second<A, B extends A>(a: A, b: B): A {
  return a;
}
function parseJSON<T>(input: string): T {
  return JSON.parse(input);
}
function printProperty<T, K extends keyof T>(obj: T, key: K) {
  console.log(obj[key]);
}
function third<A, B, C>(a: A, b: B, c: C): C {
  return c;
}
function unused<T>() {}
function identity<T>(arg: T): T {
  return arg;
}
function getProperty<T, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key];
}
function both<T>(a: T, b: T) {}
function arrayParameter<T>(items: T[]) {}
function arrayReturn<T>(count: number): T[] {
  return [];
}
function readonlyArrayReturn<T>(): readonly T[] {
  return [];
}
function readonlyArrayParameter<T>(items: readonly T[], other: ReadonlyArray<T>) {}
function genericArray<T>(items: Array<T>) {}
function genericArrayReturn<T>(): Array<T> {
  return [];
}
function tupleParameter<T>(pair: [T, T]) {}
function tupleOnce<T>(pair: [T, string]) {}
function tupleReturn<T>(): [T] {
  return [] as unknown as [T];
}
function readonlyTupleReturn<T>(): readonly [T] {
  return [] as unknown as [T];
}
function mapParameter<K, V>(map: Map<K, V>) {}
function setReturn<T>(): Set<T> {
  return new Set();
}
function promiseParameter<T>(promise: Promise<T>) {}
function unionArgument<T>(box: Set<T | null>) {}
function inferredReturn<T>(value: T) {
  return value;
}
function inferredOnce<T>(value: T) {
  return 1;
}
function inferredObject<T>(value: T) {
  return { value };
}
function inferredArray<T>(value: T) {
  return [value];
}
function inferredBox<T>(value: T) {
  return boxIt(value);
}
function inferredMapped<T>(value: T) {
  return mapIt(value);
}
function writtenMapped<T>(value: { [K in keyof T]: T[K] }) {}
function mappedOnce<T>(value: { [K in keyof T]: string }) {}
function mappedKey<T extends string>(value: { [K in T]: number }) {}
function conditional<T>(value: T extends string ? 1 : 2) {}
function conditionalTwice<T>(value: T extends string ? T : never) {}
function template<T extends string>(value: `id-${T}`) {}
function keyofParameter<T>(key: keyof T) {}
function indexedAccess<T, K extends keyof T>(value: T[K]) {}
function withDefault<T = string>(value: T) {}
function defaultUses<T, U = T>(u: U) {}
function constraintUses<T, U extends T>(u: U) {}
function constraintArray<T, U extends T[]>(u: U): U {
  return u;
}
function objectConstraint<T extends Shape>(shape: T) {
  return shape.kind;
}
function objectConstraintReturned<T extends Shape>(shape: T) {
  return shape;
}
function assertsIt<T>(value: unknown): asserts value is T {}
function isIt<T>(value: unknown): value is T {
  return true;
}
function thisParameter<T>(this: T) {}
function callbackParameter<T>(callback: (value: T) => void) {}
function callbackBoth<T>(callback: (value: T) => T) {}
function callbackReturn<T>(callback: () => T) {}
function nestedGeneric<T>(value: T) {
  return function <U>(other: U) {
    return [value, other] as const;
  };
}
function literalConstraint<T extends 'a' | 'b'>(value: T) {}
function anyConstraint<T extends any>(value: T) {}
function unknownConstraint<T extends unknown>(value: T) {}
function typeofUse<T>(value: T) {
  const copy: T = value;
  return typeof copy;
}
function bodyOnly<T>() {
  const local: T[] = [];
  return local.length;
}
function recordParameter<T extends string>(record: Record<T, number>) {}
function partialParameter<T>(value: Partial<T>) {}
function optionalParameter<T>(value?: T) {}
function restParameter<T>(...values: T[]) {}
function restTuple<T extends unknown[]>(...values: T) {}
function unionParameter<T>(value: T | null) {}
function intersectionParameter<T>(value: T & Shape) {}
function overloaded<T>(value: T): T;
function overloaded<T>(value: T, other: string): void;
function overloaded(value: unknown, other?: string): unknown {
  return value;
}

const arrowOnce = <T,>(value: T) => {};
const arrowTwice = <T,>(value: T): T => value;
const expressionOnce = function <T>(value: T) {};
declare function declaredOnce<T>(value: T): void;
declare function declaredTwice<T>(value: T): T;
export function exportedOnce<T>(value: T) {}
export default function <T>(value: T) {}

type FunctionType = <T>(value: T) => void;
type FunctionTypeTwice = <T>(value: T) => T;
type ConstructorType = new <T>(value: T) => object;
type ConstructorTypeTwice = new <T>(value: T) => T[];
interface Signatures {
  <T>(value: T): void;
  new <T>(value: T): Signatures;
  method<T>(value: T): void;
  methodTwice<T>(value: T): T;
  property: <T>(value: T) => void;
}
type ObjectType = {
  <T>(value: T): T;
  method<T>(value: T): string;
};

class Members {
  method<T>(value: T) {}
  methodTwice<T>(value: T): T {
    return value;
  }
  static shared<T>(value: T) {}
  arrow = <T,>(value: T) => {};
  overloadedMethod<T>(value: T): void;
  overloadedMethod<T>(value: T, other: T): void;
  overloadedMethod(value: unknown, other?: unknown) {}
}
abstract class AbstractMembers {
  abstract method<T>(value: T): void;
  abstract methodTwice<T>(value: T): T;
}
class Joiner<T extends string | number> {
  join(el: T, other: string) {
    return [el, other].join(',');
  }
}
class Box<T> {
  value!: T;
}
class ArrayBox<T> {
  values: T[] = [];
}
class Unused<T> {}
class ConstructorOnly<T> {
  constructor(value: T) {}
}
class ConstructorProperty<T> {
  constructor(private value: T) {}
}
class MethodReturn<T> {
  get(): T {
    return undefined as T;
  }
}
class TwoMembers<T> {
  first!: T;
  second!: T;
}
class Heritage<T> extends Array<T> {}
class Implements<T> implements Iterable<T> {
  [Symbol.iterator](): Iterator<T> {
    return [][Symbol.iterator]();
  }
}
class Indexed<T> {
  [key: string]: T;
}
class StaticBlock<T> {
  static {
    void 0;
  }
  one(value: T) {}
}
class TwoParameters<K, V> {
  map = new Map<K, V>();
  key!: K;
}
const Expression = class <T> {
  value!: T;
};
declare class Declared<T> {
  method(value: T): void;
}

// The constraint in the suggestion.
function unionConstraintArray<T extends string | number>(values: T[]) {}
function unionConstraintUnion<T extends string | number>(value: T | boolean) {}
function intersectionConstraint<T extends Shape & { id: number }>(values: T[]) {}
function conditionalConstraint<T extends (string extends 'a' ? 1 : 2)>(value: T[]) {}
function unionConstraintPlain<T extends string | number>(value: T) {}
function unionConstraintLookup<T extends 'kind' | 'length'>(value: Shape[T & 'kind']) {}
function parenthesizedArray<T extends string | number>(values: (T)[]) {}
function firstOfThree<A, B, C>(a: A, b: B, c: C): [B, C, B, C] {
  return [b, c, b, c];
}
function middleOfThree<A, /* b */ B, C>(a: A, b: B, c: C): [A, C, A, C] {
  return [a, c, a, c];
}
function lastOfThree<A, B, C>(a: A, b: B, c: C): [A, B, A, B] {
  return [a, b, a, b];
}
function multiline<
  A,
  B,
>(a: A, b: B): [A, A] {
  return [a, a];
}
export { second, parseJSON, printProperty, third, unused, identity, getProperty, both, arrowOnce, arrowTwice, expressionOnce, Members, Joiner, Box, Expression };
