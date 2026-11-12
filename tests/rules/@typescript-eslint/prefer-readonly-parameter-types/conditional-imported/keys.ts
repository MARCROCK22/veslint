// A conditional alias with a default type argument, whose false branch is another conditional
// type that has an indexed access, a conditional type with `infer` and a function type.
export type TypedKey<Point = any, Value = unknown> = unknown extends Point
  ? string | number | ((obj: Point) => Value)
  : string extends keyof Point
    ? string | number | ((obj: Point) => Value)
    :
        | {
            [K in keyof Point]: Point[K] extends Value ? (K extends string | number ? K : never) : never;
          }[keyof Point]
        | (Point extends ReadonlyArray<infer E> ? (E extends Value ? `${number}` : never) : never)
        | ((obj: Point) => Value);
// The same with a mutable branch in the first conditional type, and in the second.
export type TypedList<Point = any, Value = unknown> = unknown extends Point
  ? Value[]
  : string extends keyof Point
    ? string | number | ((obj: Point) => Value)
    : { [K in keyof Point]: K }[keyof Point] | (Point extends ReadonlyArray<infer E> ? E : never);
export type TypedSecond<Point = any, Value = unknown> = unknown extends Point
  ? string | ((obj: Point) => Value)
  : string extends keyof Point
    ? Value[]
    : { [K in keyof Point]: K }[keyof Point] | (Point extends ReadonlyArray<infer E> ? E : never);
