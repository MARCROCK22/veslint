export {};
declare const array: string[];
declare const optionalTuple: [number?, string?];
declare const unionOfArrays: string[] | number[];
declare const maybeArray: string[] | undefined;
declare const branded: string[] & { brand: true };
declare const record: Record<number, string>;
declare const anyValue: any;
declare const holder: { items: string[]; nested?: { items: number[] } };
declare const index: number;

// Reported.
delete array[0];
delete array[index + 1];
delete optionalTuple[0];
delete unionOfArrays[0];
delete branded[0];
delete (array)[0];
delete (array[0]);
delete holder.items[0];
delete maybeArray![0];
delete array[
  // a comment inside
  0
];
function constrained<T extends number[]>(values: T): void {
  delete values[0];
}
function elements<T>(values: T[]): void {
  delete values[0];
}

// Not reported.
delete maybeArray?.[0];
delete holder.nested?.items[0];
delete record[0];
delete anyValue[0];
delete anyValue.property;
const object: { key?: string } = {};
delete object.key;
function unconstrained<T extends object>(values: T): void {
  delete (values as Record<string, unknown>).key;
}
