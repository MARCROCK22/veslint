// prefer-readonly-parameter-types: parameters whose type is not deeply read-only.
interface Point {
  x: number;
  y: number;
}
interface ReadonlyPoint {
  readonly x: number;
  readonly y: number;
}
interface Nested {
  readonly point: Point;
}
interface DeepReadonly {
  readonly point: ReadonlyPoint;
  readonly list: readonly string[];
}
interface WithMethod {
  readonly value: number;
  compute(): number;
}
interface WithFunctionProperty {
  readonly compute: () => number;
}
interface Indexed {
  [key: string]: number;
}
interface ReadonlyIndexed {
  readonly [key: string]: number;
}
interface NumberIndexed {
  readonly [index: number]: string[];
}
interface Recursive {
  readonly self: Recursive;
  readonly children: readonly Recursive[];
}
interface MutableRecursive {
  self: MutableRecursive;
}
type Mutable = { value: number };
type Alias = readonly string[];
type Brand = string & { readonly __brand: 'id' };
type MutableBrand = number & { __brand: 'n' };
type BrandUnion = Brand | MutableBrand;
type NotBrand = { a: number } & { b: number };
type Cond<T> = T extends string ? readonly string[] : number[];
type ReadonlyCond<T> = T extends string ? readonly string[] : readonly number[];
enum Color {
  Red,
  Blue,
}
class Klass {
  readonly a = 1;
  #secret = 2;
  private hidden = 3;
}
class ReadonlyKlass {
  readonly a = 1;
  #secret = 2;
}
class WithMethods {
  readonly a = 1;
  method() {}
}
declare const sym: unique symbol;
interface SymbolKeyed {
  readonly [sym]: string[];
  readonly [Symbol.iterator]: () => Iterator<string>;
}

function primitives(a: string, b: number, c: boolean, d: bigint, e: symbol, f: null, g: undefined, h: unknown, i: any, j: never, k: void, l: object) {}
function literals(a: 'x', b: 1, c: true, d: Color, e: Color.Red, f: `id-${string}`) {}
function arrays(a: string[], b: readonly string[], c: Array<string>, d: ReadonlyArray<string>, e: readonly string[][], f: readonly (readonly string[])[]) {}
function tuples(a: [number, string], b: readonly [number, string], c: readonly [number[], string], d: readonly [], e: []) {}
function objects(a: Point, b: ReadonlyPoint, c: Nested, d: DeepReadonly, e: {}, f: { readonly a: number }, g: { a: number }) {}
function utilities(a: Readonly<Point>, b: Readonly<Nested>, c: Partial<ReadonlyPoint>, d: Required<ReadonlyPoint>, e: Record<string, number>, f: Readonly<Record<string, number>>, g: Pick<ReadonlyPoint, 'x'>) {}
function methods(a: WithMethod, b: WithFunctionProperty, c: WithMethods, d: () => void, e: (a: string[]) => number[], f: Function) {}
function indexed(a: Indexed, b: ReadonlyIndexed, c: NumberIndexed) {}
function recursive(a: Recursive, b: MutableRecursive) {}
function aliases(a: Mutable, b: Alias, c: Brand, d: MutableBrand, e: BrandUnion, f: NotBrand) {}
function unions(a: string | number, b: string | string[], c: readonly string[] | ReadonlyPoint, d: Point | undefined, e: ReadonlyPoint | null) {}
function intersections(a: ReadonlyPoint & { readonly z: number }, b: ReadonlyPoint & { z: number }, c: readonly string[] & { readonly extra: number }, d: string[] & { readonly extra: number }) {}
function classes(a: Klass, b: ReadonlyKlass, c: Date, d: RegExp, e: Map<string, number>, f: ReadonlyMap<string, number>, g: Set<string>, h: ReadonlySet<string>, i: Promise<string>, j: Error) {}
function symbols(a: SymbolKeyed) {}
function generic<T, U extends string[], V extends readonly string[], W extends Point>(a: T, b: U, c: V, d: W, e: T[], f: readonly T[]) {}
function conditional<T>(a: Cond<T>, b: ReadonlyCond<T>, c: T extends number ? Point : ReadonlyPoint, d: Cond<string>, e: Cond<number>) {}
function mapped<T>(a: { readonly [K in keyof T]: T[K] }, b: { [K in keyof T]: T[K] }, c: { -readonly [K in keyof ReadonlyPoint]: number }, d: { +readonly [K in 'a' | 'b']: string[] }) {}
function defaults(a: string[] = [], b = [1, 2], c: readonly string[] = [], d = 'text', e = { x: 1 }) {}
function optional(a?: string[], b?: readonly string[], c?: Point) {}
function rest(...a: string[]) {}
function readonlyRest(...a: readonly string[]) {}
function destructured({ x, y }: Point, [first]: string[], { x: renamed }: ReadonlyPoint, [head]: readonly string[]) {}
function withThis(this: Point, a: string) {}
function withReadonlyThis(this: ReadonlyPoint) {}
function inferredLiteral(a = { x: 1 } as const, b = [1, 2] as const) {}

const arrow = (a: string[]) => a;
const arrowReadonly = (a: readonly string[]) => a;
const bare = [[1], [2]].map(x => x.length);
const bareReadonly = ['a', 'b'].map(x => x.length);
const expression = function (a: Point) {};
const callbackTyped: (a: string[]) => void = a => {};
[[1]].forEach((item, index, all) => {});
declare function ambient(a: string[], b: readonly string[]): void;
function overloaded(a: string[]): void;
function overloaded(a: readonly number[]): void;
function overloaded(a: unknown): void {}
export default function (a: Point) {}

class Members {
  constructor(
    private readonly list: string[],
    public readonly safe: readonly string[],
    protected point: Point,
    plain: Point,
    readonly direct: Mutable,
  ) {}
  method(a: string[]) {}
  static staticMethod(a: readonly string[], b: Point) {}
  set value(a: string[]) {}
  overloadedMethod(a: string[]): void;
  overloadedMethod(a: readonly string[]): void;
  overloadedMethod(a: unknown): void {}
  arrowProperty = (a: Point) => {};
}
abstract class Abstract {
  abstract method(a: string[]): void;
  abstract other(a: readonly string[]): void;
}
declare class Declared {
  constructor(a: string[]);
  method(a: Point): void;
}
interface Signatures {
  (a: string[]): void;
  new (a: string[]): Signatures;
  method(a: string[]): void;
  property: (a: string[]) => void;
  readonlyMethod(a: readonly string[]): void;
  set accessor(a: Point);
}
type FunctionType = (a: string[], b: readonly string[]) => void;
type ConstructorType = new (a: string[]) => object;
type ObjectType = { method(a: string[]): void; (a: Point): void };
const objectLiteral = {
  method(a: string[]) {},
  property: function (a: Point) {},
  arrow: (a: readonly string[]) => {},
  set value(a: string[]) {},
};
