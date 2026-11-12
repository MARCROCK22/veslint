interface Box {
  value: number;
}
interface Other {
  other: string;
}
enum Color {
  Red,
  Green,
}
namespace Names {
  export type Name = string;
}
type Alias = string;
type Maybe<T> = T | undefined;

declare const maybe: string | undefined;
declare const nullable: string | null;
declare const both: string | number | null | undefined;
declare const mixed: string | number | undefined;
declare const plain: string;
declare const anyValue: any;
declare const unknownValue: unknown;
declare const box: Box | null;
declare const boxes: Array<number> | undefined;
declare const flag: boolean | undefined;
declare const color: Color | undefined;
declare const direction: 'up' | 'down' | undefined;
declare const qualified: Names.Name | undefined;
declare const aliased: Alias | undefined;
declare const generic: Maybe<string>;
declare const intersection: (Box & Other) | null;
declare const literal: 'a' | undefined;
declare const one: 1 | undefined;
declare const minusOne: -1 | undefined;
declare const big: 1n | undefined;
declare const yes: true | null;
declare const template: `abc` | undefined;
declare const pattern: `a${string}` | undefined;
declare const key: keyof Box | undefined;
declare const indexed: Box['value'] | undefined;
declare const pair: [string, number] | undefined;
declare const frozen: readonly string[] | undefined;
declare const bigValue: bigint | undefined;
declare const symbolValue: symbol | undefined;
declare const record: Record<string, number> | undefined;
declare const callback: (() => void) | undefined;
declare const shape: { a: string } | undefined;
declare const nothing: null | undefined;
declare function take(value: string): void;

// Reported: the asserted type is the original one without null and undefined.
const a = maybe as string;
const b = <string>maybe;
const c = (maybe) as (string);
const d = nullable as string;
const e = both as number | string;
const f = box as Box;
const g = boxes as number[];
const h = flag as boolean;
const i = color as Color;
const j = direction as 'up' | 'down';
const k = qualified as Names.Name;
const l = aliased as Alias;
const m = generic as string;
const n = intersection as Box & Other;
const o = maybe as typeof plain;
take(maybe as string);
const p = (maybe as string) as string;
const literals = [literal as 'a', one as 1, minusOne as -1, big as 1n, yes as true, <'a'>literal];
const templates = [template as `abc`, pattern as `a${string}`];
const others = [
  key as keyof Box,
  indexed as Box['value'],
  pair as [string, number],
  frozen as readonly string[],
  bigValue as bigint,
  symbolValue as symbol,
  record as Record<string, number>,
];

// Not reported.
const q = 'text' as const;
const r = <const>['a'];
const s = maybe as string | undefined;
const t = mixed as string;
const u = plain as string;
const v = anyValue as string;
const w = unknownValue as string;
const x = maybe as unknown;
const y = maybe as any;
const z = maybe! as string;
// Function and object literal types are new types each time.
const fresh = [callback as () => void, shape as { a: string }];
const nullish = [nothing as null, literal as undefined];

// Type parameters: an unconstrained one could be nullish.
function unconstrained<T>(value: T | undefined): T {
  return value as T;
}
function constrained<T extends string>(value: T | null): T {
  return value as T;
}
function nullableConstraint<T extends string | undefined>(value: T | null): T {
  return value as T;
}
class Self {
  me: this | undefined;
  get(): this {
    return this.me as this;
  }
}

export { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z };
export { literals, templates, others, fresh, nullish, unconstrained, constrained, nullableConstraint, Self };
