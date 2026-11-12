export {};
declare const text: string;
declare const num: number;
declare const bool: boolean;
declare const plain: { a: number };
declare const empty: {};
declare const anyValue: any;
declare const unknownValue: unknown;
declare const neverValue: never;
declare const date: Date;
declare const error: Error;
declare const regex: RegExp;
declare const url: URL;
declare const params: URLSearchParams;
declare const plainOrText: { a: number } | string;
declare const plainOrPlain: { a: number } | { b: number };
declare const plainAndText: { a: number } & string;
declare const plainAndPlain: { a: number } & { b: number };
declare const objects: { a: number }[];
declare const texts: string[];
declare const mixed: ({ a: number } | string)[];
declare const tuple: [string, { a: number }];
declare const tupleMaybe: [string, { a: number } | string];
declare const readonlyObjects: readonly { a: number }[];
declare const nested: { a: number }[][];
declare const symbolValue: symbol;
declare const fn: () => void;
class WithToString {
  toString(): string {
    return '';
  }
}
class Plain {
  value = 1;
}
class SubError extends Error {}
class Primitive {
  [Symbol.toPrimitive](): string {
    return '';
  }
}
interface PrimitiveLike {
  [Symbol.toPrimitive](hint: string): string;
}
declare const withToString: WithToString;
declare const plainInstance: Plain;
declare const subError: SubError;
declare const primitive: Primitive;
declare const primitiveLike: PrimitiveLike;
interface Generic<T> {
  value: T;
}
declare const generic: Generic<number>;
type Recursive = Recursive[];
declare const recursive: Recursive;

// Template literals.
`${text} ${num} ${bool} ${anyValue} ${unknownValue} ${neverValue}`;
`${plain}`;
`${empty}`;
`${(plain)}`;
`${date} ${error} ${regex} ${url} ${params}`;
`${plainOrText} ${plainOrPlain} ${plainAndText} ${plainAndPlain}`;
`${objects} ${texts} ${mixed} ${tuple} ${tupleMaybe} ${readonlyObjects} ${nested}`;
`${withToString} ${plainInstance} ${subError} ${primitive} ${primitiveLike}`;
`${generic} ${recursive} ${fn} ${symbolValue}`;
String.raw`${plain}`;

// `+` and `+=` with a string.
const sum1 = text + plain;
const sum2 = plain + text;
const sum3 = plain + num;
const sum4 = 'literal' + plainOrText;
let accumulated = '';
accumulated += plain;
accumulated += text;

// String(), toString(), toLocaleString() and join().
String(plain);
String(text);
String(...[plain]);
plain.toString();
plain.toLocaleString();
withToString.toString();
(plain).toString();
plain?.toString();
objects.join();
texts.join(', ');
mixed.join();
tuple.join();
plainOrPlain.toString();
nested.join();
function generics<T, U extends { a: number }, V extends string>(t: T, u: U, v: V): void {
  `${t} ${u} ${v}`;
  [u].join();
}
