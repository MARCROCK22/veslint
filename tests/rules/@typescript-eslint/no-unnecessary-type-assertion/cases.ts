interface Point {
  x: number;
  y: number;
}
interface ReadonlyPoint {
  readonly x: number;
  readonly y: number;
}
interface Named {
  name: string;
}
type Alias = Point;
declare const text: string;
declare const maybe: string | undefined;
declare const nullable: number | null;
declare const voided: string | void;
declare const literal: 'a';
declare const point: Point;
declare const readonlyPoint: ReadonlyPoint;
declare const anyValue: any;
declare const unknownValue: unknown;
declare const record: Record<string, number>;
declare const list: string[];
declare function take(value: string): void;
declare function takeMaybe(value: string | undefined): void;
declare function takeNullable(value: string | null): void;
declare function takeAny(value: any): void;
declare function takeUnknown(value: unknown): void;
declare function overloaded(value: string): void;
declare function overloaded(value: number): void;
declare function generic<T>(value: T): T;
declare function takePoint(value: Point): void;

// Non-null assertions.
const a = text!;
const b: string | undefined = maybe!;
const c: string = maybe!;
takeMaybe(maybe!);
take(maybe!);
const d = nullable!;
takeNullable(maybe!);
const e = voided!;
let assigned: string | undefined;
assigned! = 'x';
let declaredLater: number;
const f = declaredLater!;
declare let ambient: number;
const g = ambient!;
let initialized: number = 1;
const h = initialized!;
function genericNonNull<T>(value: T): T {
  return value!;
}
function constrainedNonNull<T extends string>(value: T): T {
  return value!;
}
function unknownNonNull(value: unknown): void {
  takeUnknown(value!);
  take(value! as string);
}
const i = anyValue!;
const j = point.x!;
const k = list[0]!;
function varUse(): number {
  if (text) {
    var scoped: number = 1;
  }
  return scoped!;
}

// Type assertions that do not change the type.
const l = text as string;
const m = <string>text;
const n = 3 as 3;
let o = 3 as 3;
const p = 'a' as const;
const q = [1] as const;
let r = 'b' as const;
const s = text as unknown as string;
take(literal as string);
const t: string = literal as string;
const u = (text as string).length;
const v = point as Point;
const w = point as Alias;
const x = point as ReadonlyPoint;
const y = readonlyPoint as Point;
const z = record as { [key: string]: number };
const aa = point as Point & {};
const ab = anyValue as string;
const ac = text as any;
const ad = unknownValue as string;
const ae = (() => 1)() as number;
const af = (() => {})() as void;
const ag = { x: 1, y: 2 } as Point;
const ah = {} as Point;
const ai = [text] as string[];
const aj = `a${text}` as string;
const ak = `abc` as `abc`;
const al = null as Point | null;
const am = undefined as string | undefined;
takeAny(text as any);
takeUnknown(text as unknown);
overloaded(text as string);
const an = generic(text as string);
takePoint({ x: 1, y: 2 } as Point);
const ao = text as unknown as Named;
const ap = (text as unknown) as string;
const { length } = text as string;
let reassignedText: string = text;
const aq = (reassignedText = literal as string);
reassignedText ||= literal as string;
const ar = [...(list as string[])];
const as1 = (literal as string) satisfies string;
class Holder {
  readonly field = 'x' as 'x';
  mutable = 'y' as 'y';
}
function inArrow(): void {
  const callback = generic(() => text as string);
}

export { a, b, c, d, e, f, g, h, genericNonNull, constrainedNonNull, unknownNonNull, i, j, k, varUse };
export { l, m, n, o, p, q, r, s, t, u, v, w, x, y, z, aa, ab, ac, ad, ae, af, ag, ah, ai, aj, ak, al, am };
export { an, ao, ap, length, aq, ar, as1, Holder, inArrow };
