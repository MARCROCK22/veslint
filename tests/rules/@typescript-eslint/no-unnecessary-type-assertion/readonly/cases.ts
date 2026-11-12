interface ReadonlyPoint {
  readonly x: number;
}
interface Point {
  x: number;
}
type Mapped<T> = { [K in keyof T]: T[K] };
type ReadonlyMapped<T> = { readonly [K in keyof T]: T[K] };
type Mutable<T> = { -readonly [K in keyof T]: T[K] };
declare const mapped: Mapped<ReadonlyPoint>;
declare const inlineMapped: { [K in keyof ReadonlyPoint]: ReadonlyPoint[K] };
declare const readonlyMapped: ReadonlyMapped<Point>;
declare const mutable: Mutable<ReadonlyPoint>;
declare const tuple: readonly [number];
declare const getter: { get x(): number };
const frozen = { x: 1 } as const;
declare function constant<const T>(value: T): T;
const fromCall = constant({ x: 1 });

// Readonly properties must be readonly on both sides.
const a = readonlyMapped as ReadonlyPoint;
const b = mutable as Point;
const c = tuple as [number];
const d = getter as ReadonlyPoint;
const e = frozen as { readonly x: 1 };
// A mapped type without a readonly modifier takes it from its modifiers type (the `T` of
// `keyof T`): TypeScript marks the property CheckFlags.Readonly, which is what veslint reads.
const f = inlineMapped as ReadonlyPoint;
// Not reported anyway: the alias type arguments differ.
const i = mapped as ReadonlyPoint;
// The properties a const type parameter infers are readonly (CheckFlags.Readonly).
const g = fromCall as { readonly x: 1 };
const h = fromCall as { x: 1 };

// More mapped types without a readonly modifier.
interface Mixed {
  readonly locked: number;
  open: number;
}
declare const inlineMixed: { [K in keyof Mixed]: Mixed[K] };
declare const inlinePoint: { [K in keyof Point]: Point[K] };
declare const nested: { [K in keyof ReadonlyMapped<Point>]: ReadonlyMapped<Point>[K] };
declare const picked: { [K in 'x']: ReadonlyPoint[K] };
declare const optional: { [K in keyof ReadonlyPoint]?: ReadonlyPoint[K] };
declare const unioned: { [K in keyof (ReadonlyPoint | Point)]: number };
declare const intersected: { [K in keyof (ReadonlyPoint & Point)]: number };
const j = inlineMixed as Mixed;
const k = inlineMixed as { locked: number; open: number };
const l = inlinePoint as Point;
const m = inlinePoint as ReadonlyPoint;
const n = nested as ReadonlyPoint;
const o = nested as Point;
const p = picked as Point;
const q = picked as ReadonlyPoint;
const r = optional as { readonly x?: number };
const s = optional as { x?: number };
const u = inlineMapped as Point;
const v = unioned as ReadonlyPoint;
const w = unioned as Point;
const x = intersected as ReadonlyPoint;
const y = intersected as Point;

export { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, u, v, w, x, y };
