// Assertions to qualified types of three or more levels: `x as A.B.C` is `x as (A.B.C)`.
namespace Shapes {
  export namespace Flat {
    export interface Point {
      x: number;
    }
    export namespace Deep {
      export interface Dot {
        y: number;
      }
    }
  }
}
declare const point: Shapes.Flat.Point;
declare const dot: Shapes.Flat.Deep.Dot;
declare const maybe: Shapes.Flat.Point | undefined;
const a = point as Shapes.Flat.Point;
const b = dot as Shapes.Flat.Deep.Dot;
const c = (point as Shapes.Flat.Point).x;
const d = point satisfies Shapes.Flat.Point;
const e = maybe as Shapes.Flat.Point;
const f = [point as Shapes.Flat.Point, dot as Shapes.Flat.Deep.Dot];
export { a, b, c, d, e, f };
