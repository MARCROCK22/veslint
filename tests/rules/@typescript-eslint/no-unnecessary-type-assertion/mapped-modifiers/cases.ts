// no-unnecessary-type-assertion: whether a property of an instance of a generic mapped type
// without a readonly token is readonly is asked of the type it maps over (its modifiers type: the
// `T` of `keyof T`), which veslint reads from the declaration of the mapped type and the type
// arguments of the alias.
interface ReadonlyPoint {
  readonly x: number;
}
interface Point {
  x: number;
}
interface ReadonlyAgain {
  readonly x: number;
}
interface PointAgain {
  x: number;
}
interface WithY {
  y: number;
}
type Unlocked = { -readonly [K in keyof ReadonlyPoint]: ReadonlyPoint[K] };
type Mapped<T> = { [K in keyof T]: T[K] };
type MappedParen<T> = ({ [K in keyof (T)]: T[K] });
type Chosen<T, K extends keyof T> = { [P in K]: T[P] };
type Without<T, K extends keyof T> = Chosen<T, Exclude<keyof T, K>>;
type Keys<K extends PropertyKey> = { [P in K]: number };
// The same properties, written: readonly or not, with the same alias type arguments.
type Locked<T> = { readonly x: T extends unknown ? number : never };
type Open<T> = { x: T extends unknown ? number : never };
type LockedPair<T, K> = { readonly x: [T, K] extends [unknown, unknown] ? number : never };
type OpenPair<T, K> = { x: [T, K] extends [unknown, unknown] ? number : never };

// A property that is readonly in only some parts of an intersection: readonly for
// typescript-eslint, and TypeScript does not mark it.
declare const some: Mapped<ReadonlyPoint & Point>;
const a = some as Locked<ReadonlyPoint & Point>;
const b = some as Open<ReadonlyPoint & Point>;
declare const someParen: MappedParen<ReadonlyPoint & Point>;
const c = someParen as Locked<ReadonlyPoint & Point>;
const d = someParen as Open<ReadonlyPoint & Point>;
declare const partial: Partial<ReadonlyPoint & Point>;
const e = partial as Partial<Locked<ReadonlyPoint & Point>>;
declare const chosen: Chosen<ReadonlyPoint & Point, 'x'>;
const f = chosen as LockedPair<ReadonlyPoint & Point, 'x'>;
const g = chosen as OpenPair<ReadonlyPoint & Point, 'x'>;
declare const picked: Pick<ReadonlyPoint & Point, 'x'>;
const h = picked as LockedPair<ReadonlyPoint & Point, 'x'>;
const i = picked as OpenPair<ReadonlyPoint & Point, 'x'>;
declare const without: Without<ReadonlyPoint & Point & WithY, 'y'>;
const j = without as LockedPair<ReadonlyPoint & Point & WithY, 'y'>;
const k = without as OpenPair<ReadonlyPoint & Point & WithY, 'y'>;
declare const omitted: Omit<ReadonlyPoint & Point & WithY, 'y'>;
const l = omitted as LockedPair<ReadonlyPoint & Point & WithY, 'y'>;
const m = omitted as OpenPair<ReadonlyPoint & Point & WithY, 'y'>;

// All the parts readonly, or none.
declare const all: Mapped<ReadonlyPoint & ReadonlyAgain>;
const n = all as Locked<ReadonlyPoint & ReadonlyAgain>;
const o = all as Open<ReadonlyPoint & ReadonlyAgain>;
declare const none: Mapped<Point & PointAgain>;
const p = none as Locked<Point & PointAgain>;
const q = none as Open<Point & PointAgain>;

// A property that is a namespace.
namespace Outer {
  export namespace x {
    export const value = 1;
  }
}
type LockedOuter<T> = { readonly x: T extends unknown ? typeof Outer.x : never };
type OpenOuter<T> = { x: T extends unknown ? typeof Outer.x : never };
declare const spaces: Mapped<typeof Outer>;
const r = spaces as LockedOuter<typeof Outer>;
const s = spaces as OpenOuter<typeof Outer>;

// The `length` of a readonly tuple, which TypeScript marks and typescript-eslint does not see.
type Length<T, K> = { length: [T, K] extends [unknown, unknown] ? number : never };
type LockedLength<T, K> = { readonly length: [T, K] extends [unknown, unknown] ? number : never };
declare const size: Chosen<readonly [number, ...number[]], 'length'>;
const t = size as Length<readonly [number, ...number[]], 'length'>;
const u = size as LockedLength<readonly [number, ...number[]], 'length'>;

// Keys that are not a `keyof`: the modifiers type is the unknown type.
type LockedKeys<K> = { readonly x: K extends unknown ? number : never };
type OpenKeys<K> = { x: K extends unknown ? number : never };
declare const keys: Keys<'x'>;
const v = keys as LockedKeys<'x'>;
const w = keys as OpenKeys<'x'>;
declare const record: Record<'x', number>;
const x = record as OpenPair<'x', number>;
const y = record as LockedPair<'x', number>;

// A mapped type over a mapped type, and the type arguments of an alias that names another.
type Twice<T> = Mapped<Mapped<T>>;
declare const twice: Twice<ReadonlyPoint & Point>;
const z = twice as Locked<ReadonlyPoint & Point>;
const aa = twice as Open<ReadonlyPoint & Point>;
declare const mutable: Mapped<Unlocked & Point>;
const ab = mutable as Open<Unlocked & Point>;
const ac = mutable as Locked<Unlocked & Point>;

// Instances without an alias (what a generic function returns): the modifiers type is the object
// type of the template of the instance (`T[K]`), which tsgo gives since TypeScript 7.1.
declare function mapAll<T>(value: T): { [K in keyof T]: T[K] };
declare function mapOptional<T>(value: T): { [K in keyof T]?: T[K] };
declare function mapWrapped<T>(value: T): { [K in keyof T]: Promise<T[K]> };
declare const pointBoth: ReadonlyPoint & Point;
declare const pointsMutable: Point & PointAgain;
const ad = mapAll(pointBoth) as Locked<ReadonlyPoint & Point>;
const ae = mapAll(pointBoth) as Open<ReadonlyPoint & Point>;
const af = mapAll(pointsMutable) as Locked<Point & PointAgain>;
const ag = mapAll(pointsMutable) as Open<Point & PointAgain>;
const ah = mapAll(Outer) as LockedOuter<typeof Outer>;
const ai = mapAll(Outer) as OpenOuter<typeof Outer>;
const aj = mapOptional(pointBoth) as { readonly x?: number };
const ak = mapOptional(pointBoth) as { x?: number };
const al = mapWrapped(pointBoth) as { readonly x: Promise<number> };
const am = mapWrapped(pointBoth) as { x: Promise<number> };
declare function pickSome<T, K extends keyof T>(value: T, ...keys: K[]): { [P in K]: T[P] };
const an = pickSome(pointBoth, 'x') as { readonly x: number };
const ao = pickSome(pointBoth, 'x') as { x: number };

export { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z, aa, ab, ac };
export { ad, ae, af, ag, ah, ai, aj, ak, al, am, an, ao };
