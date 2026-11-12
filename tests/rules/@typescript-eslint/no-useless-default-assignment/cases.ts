interface Options {
  required: string;
  optional?: number;
  maybe: string | undefined;
  nested: { inner: boolean; innerOptional?: string };
  'quoted key': number;
  42: string;
}
declare const options: Options;
declare const either: Options | { required: string; optional: number };
declare const flag: boolean;
declare const pair: [string, number | undefined];
declare const triple: [string, number, boolean?];
declare const list: string[];
declare const anyValue: any;
declare const key: 'required';
declare function takesCallback(callback: (value: string, rest?: number) => void): void;
declare function takesRest(callback: (...values: string[]) => void): void;
declare function takesGeneric<T>(callback: (value: T) => void): void;
declare function takesAny(callback: (value: any) => void): void;
declare function takesUnion(callback: ((value: string) => void) | ((value: number) => void)): void;

// `= undefined` defaults.
function undefinedDefault(value = undefined): void {}
function annotated(value: string | undefined = undefined): void {}
function annotatedAny(value: any = undefined): void {}
function annotatedRequired(value: string = (undefined)!): void {}
function annotatedNarrow(value: string = undefined as never): void {}
const { required: renamed = undefined } = options;
const [first = undefined] = list;
const { shorthand = undefined } = { shorthand: 1 };
let assigned: number | undefined;
({ optional: assigned = undefined } = options);
declare function declared(value?: string | undefined, other: string = undefined): void;
type FunctionType = (value: string = undefined) => void;
class Holder {
  constructor(private kept: string | undefined = undefined, readonly other = 'm') {}
  method(value = 'l'): void {}
  method2(value: string | undefined = undefined): void {}
}

// Destructuring defaults of properties that are not optional.
const { required = 'x', optional = 1, maybe = 'y' } = options;
const { nested: { inner = true, innerOptional = 'z' } } = options;
const { 'quoted key': quoted = 2, 42: numeric = 'n', [key]: computed = 'c' } = options;
const { required: other = 'a' } = flag ? options : options;
const { optional: fromEither = 2 } = flag ? options : either;
const { optional: fromLiteral = 3 } = flag ? { optional: 1 } : { optional: 2 };
const { optional: fromPartial = 3 } = flag ? { optional: 1 } : {};
const { optional: fromLogical = 4 } = options || { optional: 5 };
const { optional: fromParens = 6 } = (flag ? { optional: 1 } : { optional: 2 });
const [tupleFirst = 'b', tupleSecond = 4] = pair;
const [, , third = true, fourth = 1] = triple;
const [listFirst = 'c'] = list;
const [[deep = 'd'] = ['e']] = [list];
const { anything = 1 } = anyValue;
function destructuredParameter({ required = 'd', optional = 5 }: Options): void {}
function destructuredWithDefault({ required = 'e' }: Options = options): void {}
function destructuredThis(this: Window, { required = 'f' }: Options): void {}
const destructuredArrow = ([a = 'g', b = 1]: [string, number]): void => {};
const objectMethods = {
  method({ required = 'h' }: Options): void {},
};
let reassigned: string;
({ required: reassigned = 'i' } = options);
for (const { required: looped = 'j' } of [options]) {
}

// Parameters of callbacks with a contextual type.
takesCallback((value = 'f', rest = 6) => {});
takesCallback(function (value = 'g') {});
takesRest((first = 'h') => {});
takesGeneric((value = 'i') => {});
takesAny((value = 'k') => {});
takesUnion((value = 'u') => {});
const annotatedCallback: (value: string) => void = (value = 'j') => {};
const annotatedOptional: (value?: string) => void = (value = 'j') => {};
const typed: { method(value: string): void } = {
  method(value = 'm') {},
};
function declaration(value = 'k'): void {}

export { undefinedDefault, annotated, annotatedAny, annotatedRequired, annotatedNarrow, renamed, first, shorthand };
export { declared, Holder, required, optional, maybe, inner, innerOptional, quoted, numeric, computed };
export { other, fromEither, fromLiteral, fromPartial, fromLogical, fromParens, tupleFirst, tupleSecond, third, fourth };
export { listFirst, deep, anything, destructuredParameter, destructuredWithDefault, destructuredThis };
export { destructuredArrow, objectMethods, annotatedCallback, annotatedOptional, typed, declaration };
export type { FunctionType };
