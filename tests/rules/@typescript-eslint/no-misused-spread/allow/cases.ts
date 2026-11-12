export {};
declare const text: string;
declare const literal: 'abc';
declare const template: `id-${string}`;
declare const textOrNumbers: string | number[];
declare const numbers: number[];
declare const tuple: [number, string];
declare const promise: Promise<number>;
declare const maybePromise: Promise<number> | undefined;
declare const fn: () => void;
declare const fnWithProps: { (): void; extra: number };
declare const map: Map<string, number>;
declare const readonlyMap: ReadonlyMap<string, number>;
declare const weakMap: WeakMap<object, number>;
declare const set: Set<number>;
declare const iterable: Iterable<number>;
declare const plain: { a: number };
declare const anyValue: any;
declare const unknownValue: unknown;
declare const branded: string & { brand: true };
class Box {
  value = 1;
}
class Fresh {
  static shared = 1;
}
declare const box: Box;
const ClassExpression = class {
  value = 1;
};
declare const expressionInstance: InstanceType<typeof ClassExpression>;
function generic<T extends string>(value: T): string[] {
  return [...value];
}
declare function takesAny(...values: unknown[]): void;
class CustomMap extends Map<string, number> {}
declare const customMap: CustomMap;
interface CustomPromise extends Promise<number> {}
declare const customPromise: CustomPromise;

// Spreads in arrays and calls: strings.
const a1 = [...text];
const a2 = [...literal];
const a3 = [...template];
const a4 = [...textOrNumbers];
const a5 = [...branded];
const a6 = [...numbers];
takesAny(...text);
takesAny(...numbers);
const a7 = new Set(...[text]);

// Spreads in objects.
const o1 = { ...promise };
const o2 = { ...maybePromise };
const o3 = { ...customPromise };
const o4 = { ...fn };
const o5 = { ...fnWithProps };
const o6 = { ...map };
const o7 = { ...readonlyMap };
const o8 = { ...weakMap };
const o9 = { ...customMap };
const o10 = { ...numbers };
const o11 = { ...tuple };
const o12 = { ...set };
const o13 = { ...iterable };
const o14 = { ...box };
const o15 = { ...Box };
const o16 = { ...Fresh };
const o17 = { ...ClassExpression };
const o18 = { ...expressionInstance };
const o19 = { ...plain };
const o20 = { ...anyValue };
const o21 = { ...(unknownValue as object) };
const o22 = { a: 1, ...(map), b: 2 };
const o23 = { ...generic };
class Generic<T> {
  value?: T;
}
const o24 = { ...(Generic<number>) };
