// require-array-sort-compare: `sort` and `toSorted` without a compare function on arrays.
declare const numbers: number[];
declare const strings: string[];
declare const readonlyNumbers: readonly number[];
declare const mixed: (string | number)[];
declare const anyArray: any[];
declare const anything: any;
declare const tuple: [number, number];
declare const stringTuple: [string, string];
declare const emptyTuple: [];
declare const unionOfArrays: number[] | boolean[];
declare const arrayOrString: number[] | string;
declare const arrayOrTuple: number[] | [number];
declare const maybe: number[] | undefined;
declare const literals: ('a' | 'b')[];
declare const templates: `id-${number}`[];
declare const stringOrStrings: string[] | 'x'[];
declare const nested: number[][];
declare const custom: { sort(): void; toSorted(): void };
declare const arrayLike: ArrayLike<number>;
declare const typed: Uint8Array;
declare const set: Set<number>;
declare const compare: (a: number, b: number) => number;
declare const key: 'sort';
declare const dynamic: string;

numbers.sort();
numbers.toSorted();
numbers.sort(compare);
numbers.toSorted(compare);
numbers.sort(undefined);
strings.sort();
strings.toSorted();
readonlyNumbers.toSorted();
mixed.sort();
anyArray.sort();
anything.sort();
tuple.sort();
stringTuple.sort();
emptyTuple.sort();
unionOfArrays.sort();
arrayOrString.sort;
arrayOrTuple.sort();
maybe?.sort();
maybe!.sort();
(maybe?.sort)();
maybe?.sort?.();
literals.sort();
templates.sort();
stringOrStrings.sort();
nested.sort();
nested[0].sort();
custom.sort();
custom.toSorted();
typed.sort();
set.forEach(x => x);
numbers['sort']();
numbers[`sort`]();
numbers[key]();
numbers[dynamic as 'sort']();
(numbers).sort();
(numbers.sort)();
numbers.sort!();
numbers
  .slice()
  .sort();
[1, 2, 3].sort();
['a', 'b'].sort();
[1, 'a'].sort();
[].sort();
new Array<number>(3).sort();
Array.from(arrayLike).sort();
numbers.map(String).sort();
numbers.filter(Boolean).sort().reverse();
numbers.sort /* no arguments */ ();
numbers.sort(/* still none */);
numbers.sort(...[compare]);
numbers.sort``;
new (numbers.sort as any)();

function generic<T extends number[], U extends string[], V, W extends readonly unknown[]>(
  t: T,
  u: U,
  v: V[],
  w: W,
  x: T | U,
) {
  t.sort();
  u.sort();
  v.sort();
  w.toSorted();
  x.sort();
}

class Sorter extends Array<number> {
  run() {
    this.sort();
    super.sort();
  }
}

interface Box {
  items: number[];
  names?: string[];
}
function boxes(box: Box, list: Box[]) {
  box.items.sort();
  box.names?.sort();
  list.sort();
  list.map(b => b.items).flat().sort();
}

type Alias = number[];
type Names = string[];
declare const alias: Alias;
declare const names: Names;
alias.sort();
names.sort();

enum Color {
  Red = 'red',
  Blue = 'blue',
}
enum Size {
  Small,
  Large,
}
declare const colors: Color[];
declare const sizes: Size[];
colors.sort();
sizes.sort();
