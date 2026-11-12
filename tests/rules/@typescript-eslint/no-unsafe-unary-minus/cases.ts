export {};
declare const numberValue: number;
declare const bigintValue: bigint;
declare const literalNumber: 5;
declare const anyValue: any;
declare const neverValue: never;
declare const unknownValue: unknown;
declare const textValue: string;
declare const booleanValue: boolean;
declare const objectValue: { a: number };
declare const maybeNumber: number | undefined;
declare const numberOrBigint: number | bigint;
declare const nullValue: null;
enum NumericEnum {
  A,
  B,
}
enum TextEnum {
  A = 'a',
  B = 'b',
}
declare const numericMember: NumericEnum;
declare const textMember: TextEnum;

// Not reported: numbers, bigints, `any` and `never`.
-numberValue;
-bigintValue;
-literalNumber;
-anyValue;
-neverValue;
-numberOrBigint;
-numericMember;
-NumericEnum.A;
-1;
-1n;
-(numberValue);
- -numberValue;
type Negative = -1;
type NegativeBig = -1n;
enum WithNegative {
  A = -1,
}
function constrained<T extends number>(value: T): number {
  return -value;
}

// Reported.
-unknownValue;
-textValue;
-'5';
-booleanValue;
-true;
-objectValue;
-maybeNumber;
-nullValue;
-textMember;
-TextEnum.A;
-[];
-{};
-(textValue as string);
- -textValue;
function unconstrained<T>(value: T): number {
  return -value;
}
function constrainedText<T extends string>(value: T): number {
  return -value;
}
