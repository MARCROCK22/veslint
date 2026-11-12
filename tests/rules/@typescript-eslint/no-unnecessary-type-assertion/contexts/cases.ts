interface Point {
  x: number;
}
interface Box<T> {
  _phantom?: T;
}
interface WithGeneric {
  map<U>(value: U): U;
}
interface WithoutGeneric {
  map(value: number): number;
}
declare const text: string;
declare const literal: 'a';
declare const point: Point;
declare const box: Box<string>;
declare const withoutGeneric: WithoutGeneric;
declare const maybePoint: Point | undefined;
declare function overloaded(value: string): void;
declare function overloaded(value: 'a' | 'b'): void;
declare function overloadedSame(value: string): void;
declare function overloadedSame(value: string, other: number): void;
declare function overloadedRest(...values: string[]): void;
declare function overloadedRest(value: number): void;
declare function generic<T>(value: T): T;
declare function genericBox<T>(value: Box<T>): T;
declare function takeGeneric(value: WithGeneric): void;
declare function takeUnion(value: { kind: 'a'; value: string } | { kind: 'b'; value: number }): void;
declare function takeAny(value: any): void;
declare const consumer: { take(value: string): void };

// isArgumentToOverloadedFunction.
overloaded(literal as string);
overloadedSame(literal as string);
overloadedRest(literal as string);
new Promise<string>((resolve) => resolve(literal as string));
// isInGenericContext and phantom type arguments.
const a = generic(literal as string);
const b = genericBox(box as Box<number>);
const c = generic(() => literal as string);
const d = generic(() => {
  return literal as string;
});
const e = generic<string>(literal as string);
consumer.take(literal as string);
// genericsMismatch.
takeGeneric(withoutGeneric as unknown as WithGeneric);
// isPropertyInProblematicContext.
takeUnion({ kind: 'a', value: literal as string });
const f = { x: literal as string } satisfies { x: string };
const g = generic({ x: literal as string }) satisfies { x: string };
// any casts and contexts.
takeAny(text as any);
const h: string = text as any;
const i = maybePoint ?? (point as any);
const j: Point = point as Point;
// IIFEs.
const k = (function (): string {
  return text;
})() as string;
const l = ((): undefined => undefined)() as undefined;
const m = (() => undefined)() as void;

export { a, b, c, d, e, f, g, h, i, j, k, l, m };
