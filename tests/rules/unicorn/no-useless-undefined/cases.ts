declare const array: number[];
declare const index: number;
declare const items: number[][];
declare function fn(...values: unknown[]): unknown;

// `return undefined`, reported with a fix.
function returnUndefined() {
	return undefined;
}
function returnParenthesized() {
	return (undefined);
}
function returnOnNextLine() {
	return (
		undefined
	);
}
function returnUndefinedType(): undefined {
	return undefined;
}
function returnVoid(): void {
	return undefined;
}
const returnInArrow = () => {
	return undefined;
};
class Returns {
	method() {
		return undefined;
	}
	property = function () {
		return undefined;
	};
}

// `return undefined` with a return type that is not `undefined` or `void`: not reported.
function returnUnion(): number | undefined {
	return undefined;
}
function returnUnknown(): unknown {
	return undefined;
}
const returnArrowUnion = (): string | undefined => {
	return undefined;
};
function outerWithType(): number | undefined {
	const inner = () => {
		return undefined;
	};
	inner();
	return undefined;
}

// `yield undefined`.
function* generator() {
	yield undefined;
	yield (undefined);
	yield* undefined as unknown as number[];
	const value = yield undefined;
	fn(value);
}

// `() => undefined`.
const arrowBody = () => undefined;
const arrowBodyParenthesized = () => (undefined);
const arrowWithParameter = (a: number) => /* keep */ undefined;
const arrowWithReturnType = (): undefined => undefined;
fn(() => undefined);
function withArrowInside(): number {
	fn(() => undefined);
	return 1;
}

// `let foo = undefined`.
let letUndefined = undefined;
let letTyped: string | undefined = undefined;
let letParenthesized = (undefined);
let letComment = /* keep */ undefined;
let letCommentAfter = undefined /* after */;
let letA = undefined, letB = 1, letC = undefined;
var varUndefined = undefined;
const constUndefined = undefined;
let {letPattern} = undefined as unknown as {letPattern: number};
for (let loop = undefined; loop; ) {}

// Default values.
const {foo = undefined} = {foo: 1};
const [bar = undefined] = [1];
function parameter(a = undefined) {}
function typedParameter(a: number | undefined = undefined) {}
function optionalParameter(a?: number = undefined) {}
function parameterComment(a = /* keep */ undefined) {}
function parameterParenthesized(a = ((undefined))) {}
const arrowParameter = (a = undefined) => a;
const functionExpressionParameter = function (a: string = undefined) {};
function destructuredParameter({a = undefined}: {a?: number}) {}
function patternParameter({a}: {a: number} = undefined) {}
class Parameters {
	constructor(private readonly value = undefined) {}
	method(a = undefined) {}
	setter(a: number = undefined, b = 2) {}
}

// Conditional indexed access, reported with a suggestion.
const lower1 = index >= 0 ? array[index] : undefined;
const lower2 = index < 0 ? undefined : array[index];
const lower3 = 0 <= index ? array[index] : undefined;
const lower4 = 0 > index ? undefined : array[index];
const lower5 = index > -1 ? array[index] : undefined;
const lower6 = -1 < index ? array[index] : undefined;
const lower7 = index <= -1 ? undefined : array[index];
const offset1 = index >= 1 ? array[index - 1] : undefined;
const offset2 = index > 1 ? array[index - 2] : undefined;
const offset3 = index - 1 >= 0 ? array[index - 1] : undefined;
const upper1 = index < array.length ? array[index] : undefined;
const upper2 = index <= array.length - 1 ? array[index] : undefined;
const upper3 = array.length > index ? array[index] : undefined;
const upper4 = index >= array.length ? undefined : array[index];
const upper5 = array.length - 1 < index ? undefined : array[index];
const typed1 = (index as number) >= 0 ? (array[index] as number) : undefined;
const typed2 = index >= 0 ? array[index]! : undefined;
const typed3 = index >= 0 ? array[index as number] satisfies number : undefined;
const nested = index >= 0 ? items[0][index] : undefined;
const parenthesized = (index >= 0 ? array[index] : undefined);
function returnConditional() {
	return(index) >= 0 ? array[index] : undefined;
}
for (const value of(index >= 0 ? items[index] : undefined)!) {}
fn(index >= 0 ? array[index] : undefined);
let semicolonNeeded = 1
;(index >= 0 ? array[index] : undefined)
fn(semicolonNeeded)
semicolonNeeded
index >= 0 ? [array][index] : undefined

// Reported without a suggestion.
(index >= 0 ? array[index] : undefined as unknown as Function)();
delete (index >= 0 ? array[index] : undefined);
const withComment = index >= 0 ? /* keep */ array[index] : undefined;

// Conditional, not reported.
const wrongBound1 = index > 0 ? array[index] : undefined;
const wrongBound2 = index >= 1 ? array[index] : undefined;
const wrongBound3 = index <= array.length ? array[index] : undefined;
const wrongBound4 = index < array.length ? undefined : array[index];
const wrongBound5 = index >= 0 ? undefined : array[index];
const otherArray = index < items.length ? array[index] : undefined;
const offsetUpper = index < array.length ? array[index - 1] : undefined;
const notComputed = index >= 0 ? array.length : undefined;
const optional = index >= 0 ? array?.[index] : undefined;
const optionalInTest = index >= 0 ? array[index] : undefined;
const sideEffect = index >= 0 ? array[fn() as number] : undefined;
const sideEffectObject = index >= 0 ? (fn() as number[])[index] : undefined;
const equality = index === 0 ? array[index] : undefined;
const bothUndefined = index >= 0 ? undefined : undefined;
const notUndefined = index >= 0 ? array[index] : null;
const otherIndex = index >= 0 ? array[index + 1] : undefined;
const notInteger = index >= 0.5 ? array[index] : undefined;
const zeroOffset = index >= 0 ? array[index - 0] : undefined;
const optionalLength = index < array?.length ? array[index] : undefined;

// Not reported.
fn(undefined);
fn(1, undefined);
const objectValue = {undefined: 1, value: undefined};
const arrayValue = [undefined];
if (letUndefined === undefined) {}
export {lower1, lower2, lower3, lower4, lower5, lower6, lower7, offset1, offset2, offset3, upper1, upper2, upper3, upper4,
	upper5, typed1, typed2, typed3, nested, parenthesized, withComment, wrongBound1, wrongBound2, wrongBound3,
	wrongBound4, wrongBound5, otherArray, offsetUpper, notComputed, optional, optionalInTest, sideEffect,
	sideEffectObject, equality, bothUndefined, notUndefined, otherIndex, notInteger, zeroOffset, optionalLength,
	objectValue, arrayValue, letA, letB, letC, varUndefined, constUndefined, letPattern, foo, bar, letTyped,
	letParenthesized, letComment, letCommentAfter, arrowBody, arrowBodyParenthesized, arrowWithParameter,
	arrowWithReturnType, returnInArrow, arrowParameter, functionExpressionParameter, returnArrowUnion};
