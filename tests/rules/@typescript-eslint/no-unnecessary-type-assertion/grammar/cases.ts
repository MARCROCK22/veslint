// Expression syntax tree-sitter reads differently from TypeScript.
type A = { a: 1 };
type B = { b: 2 };
declare const ab: A | B;
declare const Ctor: new () => object;
declare const n: number;
const u = ab as
  | A
  | B;
const made = new Ctor!();
const less = n! < (-2);
export { u, made, less };

// A union and an intersection that start with `|` and `&` in the other assertions.
declare const both: A & B;
const angle = <| A | B>ab;
const narrowed = ab as | A;
const intersected = both as
  & A
  & B;
export { angle, narrowed, intersected };

// The target of a rest element in parentheses.
declare let restTarget: number[];
declare const restSource: number[];
[...(restTarget as number[])] = restSource;
[...(restTarget)] = restSource;

// Targets of a destructuring assignment in parentheses or with a type assertion.
declare let first: number;
declare let second: string;
declare let maybe: number | undefined;
declare let others: number[];
declare const pair: [number, string];
declare const triple: [number, string, ...number[]];
declare const record: { k: number; j: string };
declare const matrix: number[][];
declare const holder: { n: number; items: string[] };
[first as number, (second)] = pair;
[(first as number), second as string] = pair;
[<number>first, second satisfies string] = pair;
[maybe!, (second)] = pair;
({ k: (first), j: second as string } = record);
({ k: <number>first, j: (second) = 'a' } = record);
for ([(first as number)] of matrix) {
}
for ([first as number] of matrix) {
}
for (first as number of matrix[0]) {
}
[(first) = 1, (second) = 'a', ...(others as number[])] = triple;
[first, second, ...others as number[]] = triple;
[(holder.n), holder.items[0] as string] = pair;
[first as unknown as number, ((second))] = pair;
const copied = [(first), second as string, <number>maybe!];
export { copied };
