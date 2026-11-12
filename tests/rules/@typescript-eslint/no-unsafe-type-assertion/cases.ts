// no-unsafe-type-assertion: assertions that narrow a type or involve `any`.
declare const text: string;
declare const textOrNumber: string | number;
declare const anyValue: any;
declare const unknownValue: unknown;
declare const neverValue: never;
declare const maybeText: string | undefined;
declare const nullable: string | null;
declare const anyArray: any[];
declare const anySet: Set<any>;
declare const textSet: Set<string>;
declare const anyPromise: Promise<any>;
declare const record: Record<string, unknown>;
declare const point: { x: number; y: number };
declare const partial: { x?: number };
declare const tuple: [number, string];
declare const fn: (a: string) => number;
declare const literal: 'a' | 'b';
declare const obj: object;
declare const num: number;

// Widening is safe.
text as string;
text as string | number;
text as unknown;
literal as string;
point as { x: number };
tuple as (number | string)[];
neverValue as string;
null as string | null;
undefined as undefined;
num as number | bigint;

// Narrowing.
textOrNumber as string;
textOrNumber as number;
maybeText as string;
nullable as string;
text as 'a';
text as 'a' | 'b';
num as 1;
unknownValue as string;
unknownValue as { a: number };
obj as { a: number };
record as { a: number };
partial as { x: number };
point as { x: number; y: number; z: number };
tuple as [number, string, boolean];
fn as (a: string | number) => number;
fn as (a: 'x') => number;
fn as (a: string) => 1;
text as never;
num as unknown as string;
(textOrNumber as unknown) as string;
<string>textOrNumber;
<'a'>text;
<unknown>text;

// any.
anyValue as string;
anyValue as unknown;
anyValue as any;
anyValue as string[];
anyArray as string[];
anyArray as unknown[];
anyArray as any[];
anySet as Set<string>;
anySet as Set<unknown>;
anyPromise as Promise<string>;
text as any;
unknownValue as any;
textSet as Set<any>;
[text] as any[];
<any>text;
<string>anyValue;
new Map() as Map<string, number>;
new Map<any, any>() as Map<string, number>;
(missingName as string);
(missingName.length as number);
text as MissingType;

// Object literals: excess properties do not count.
({ a: 1, b: 2 }) as { a: number };
({ a: 1 }) as { a: number; b: number };
({ a: 1 }) as { a: 1 };
({ a: 'x' }) as { a: 'x' | 'y' };
({}) as { a?: number };
({}) as { a: number };
[1, 2] as [number, number];
[1, 2] as number[];
[] as string[];
({ a: anyValue }) as { a: string };
({ a: [anyValue] }) as { a: string[] };

// const assertions and satisfies are never reported.
'a' as const;
[1, 2] as const;
({ a: 1 }) as const;
<const>'b';
text satisfies string;
anyValue satisfies string;

// Type parameters.
function unconstrained<T>(value: string, other: T) {
  value as T;
  other as T;
  other as string;
  anyValue as T;
  unknownValue as T;
  <T>value;
}
function constrained<T extends string, U extends number, V extends T>(value: string, t: T, v: V) {
  value as T;
  value as U;
  t as V;
  v as T;
  t as string;
  'a' as T;
  num as T;
  value as V;
}
function keyed<T extends object, K extends keyof T>(target: T, key: string, k: K) {
  key as K;
  key as keyof T;
  k as string;
  target[k] as string;
  target as { a: number };
}
class Base {
  base = 1;
}
class Derived extends Base {
  derived = 2;
}
declare const base: Base;
declare const derived: Derived;
base as Derived;
derived as Base;
function self<T extends Base>(this: Base, value: Base) {
  this as Derived;
  value as T;
}

enum Color {
  Red,
  Blue,
}
declare const color: Color;
color as Color.Red;
Color.Red as Color;
num as Color;
color as number;
text as `id-${string}`;
`id-${num}` as `id-${number}`;

declare function overloaded(a: string): string;
declare function overloaded(a: number): number;
overloaded as (a: string) => string;
overloaded as (a: boolean) => boolean;
JSON.parse(text) as { a: number };
Object.keys(point) as ('x' | 'y')[];
document.getElementById('a') as HTMLInputElement;
document.querySelector('a')!;
(text as unknown as number[]).length;
