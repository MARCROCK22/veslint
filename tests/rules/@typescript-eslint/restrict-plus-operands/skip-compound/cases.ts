export {};
declare const num: number;
declare const num2: number;
declare const text: string;
declare const big: bigint;
declare const bool: boolean;
declare const anyValue: any;
declare const unknownValue: unknown;
declare const neverValue: never;
declare const sym: symbol;
declare const nul: null;
declare const undef: undefined;
declare const maybeText: string | undefined;
declare const regex: RegExp;
declare const date: Date;
declare const obj: { a: number };
declare const arr: string[];
declare const textOrObject: string | { a: number };
declare const both: { a: number } & { b: string };
declare const template: `id-${string}`;
declare const literalOne: 1;
declare const literalText: 'a';
enum NumericEnum {
  A,
  B,
}
enum TextEnum {
  A = 'a',
}
declare const numericMember: NumericEnum;
declare const textMember: TextEnum;

// Valid with the default options.
num + num2;
text + text;
literalOne + num;
literalText + text;
template + text;
big + 1n;
text + num;
text + bool;
text + anyValue;
text + nul;
text + maybeText;
text + regex;
numericMember + num;
textMember + text;
function constrained<T extends number>(value: T): number {
  return value + 1;
}

// Invalid operands.
num + big;
big + num;
text + sym;
sym + text;
text + unknownValue;
text + neverValue;
text + obj;
obj + text;
arr + text;
date + 1;
text + textOrObject;
both + text;
regex + num;
num + regex;
(obj) + (text);

// Compound assignments.
let total = 0;
total += big;
let message = '';
message += obj;
message += text;
