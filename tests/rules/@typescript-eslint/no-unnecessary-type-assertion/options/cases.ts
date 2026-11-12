interface Point {
  x: number;
}
declare const point: Point;
declare const text: string;
declare const count: number;

// Ignored type names (the text of the type annotation).
const a = point as Point;
const b = text as string;
const c = count as number;
const d = text as (string);
// Literal const assertions are checked.
const e = 'a' as const;
let f = 'b' as const;
const g = [1] as const;

export { a, b, c, d, e, f, g };
