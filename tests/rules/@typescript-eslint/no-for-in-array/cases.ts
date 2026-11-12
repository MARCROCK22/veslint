export {};
declare const array: string[];
declare const tuple: [number, string];
declare const readonlyArray: readonly number[];
declare const text: string;
declare const literalText: 'abc';
declare const record: Record<string, number>;
declare const numberRecord: Record<number, string>;
declare const arrayLike: { [index: number]: string; length: number };
declare const arrayLikeTextLength: { [index: number]: string; length: string };
declare const arrayLikeLiteralLength: { [index: number]: string; length: 2 };
declare const maybeArray: string[] | undefined;
declare const textOrArray: number | string[];
declare const branded: string[] & { brand: true };
declare const anyValue: any;
declare const unknownValue: unknown;
declare const plainObject: { a: number };
declare const bytes: Uint8Array;
declare const map: Map<string, number>;
declare const nodes: ArrayLike<number>;

// Reported: array-like types.
for (const key in array) {
}
for (const key in tuple) {
}
for (const key in readonlyArray) {
}
for (const key in text) {
}
for (const key in literalText) {
}
for (const key in arrayLike) {
}
for (const key in arrayLikeLiteralLength) {
}
for (const key in maybeArray) {
}
for (const key in textOrArray) {
}
for (const key in branded) {
}
for (const key in bytes) {
}
for (const key in nodes) {
}
for (const key in (array)) {
}
let assigned: string;
for (assigned in array) {
}
outer: for (const key in array) {
  break outer;
}
for (
  const key
  in array
) {
}

// Not reported.
for (const key in record) {
}
for (const key in numberRecord) {
}
for (const key in arrayLikeTextLength) {
}
for (const key in anyValue) {
}
for (const key in unknownValue as object) {
}
for (const key in plainObject) {
}
for (const key in map) {
}
for (const value of array) {
}
async function iterate(): Promise<void> {
  for await (const value of array) {
  }
}

// Generics use their constraint.
function constrained<T extends number[]>(value: T): void {
  for (const key in value) {
  }
}
function unconstrained<T>(value: T): void {
  for (const key in value as T & object) {
  }
}
function nested(): void {
  for (const key in arguments) {
  }
}
