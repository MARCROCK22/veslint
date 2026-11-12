// no-useless-default-assignment: the fix removes the default, from the end of the left side; for
// `= undefined` on a parameter that may be undefined it also adds `?` after the name.
// Non-ASCII text before the ranges: ñ 😀 日本語.
interface Options {
  required: string;
  nested: { inner: boolean };
}
declare const options: Options;
declare const pair: [string, number];
declare const list: string[];
declare function takesCallback(callback: (value: string, other: number) => void): void;

// preferOptionalSyntax: `?` after the name and no default.
function p1(a: string | undefined = undefined): void {}
function p2(a /* name */ : /* type */ string | undefined /* before */ = /* after */ undefined): void {}
function p3(a: any = undefined, b: unknown = (undefined), c: undefined = ((undefined))): void {}
function p4({ required }: Options | undefined = undefined): void {}
function p5([first]: string[] | undefined = undefined): void {}
class P6 {
  constructor(private kept: string | undefined = undefined, public readonly other: number | undefined = undefined) {}
  method(value: string | undefined = undefined): void {}
}
const p7 = (a: string | undefined = undefined, ñ: '😀' | undefined = undefined) => a ?? ñ;
function p8(
  a: string | undefined
    = undefined,
  b: number
    | undefined = // the default
    undefined,
): void {}
function p9(\u0061bc: string | undefined = undefined, d\u{65}f: number | undefined = undefined): void {}

// uselessUndefined: only the default goes.
function u1(a = undefined, b: string = undefined as never, c = (undefined)): void {}
const { required: u2 = undefined } = options;
const [u3 = undefined] = list;
const { u4 = undefined } = { u4: 1 };
let u5: string | undefined;
({ required: u5 = undefined } = options);
[u5 = undefined] = list;
type U6 = (value: string = undefined) => void;

// uselessDefaultAssignment.
const { required = 'x' } = options;
const { required: d1 = 'x', nested: { inner = true } } = options;
const [d2 = 'a', d3 = 1] = pair;
function d4({ required = 'd' }: Options, [e = 'e']: [string]): void {}
takesCallback((value = 'f', other = 6) => {});
takesCallback(function (value = 'g') {});
let d5: string;
({ required: d5 = 'h' } = options);
// Parentheses, comments and several lines in the default.
const { required: e1 = ('x') } = options;
const { required: e2 = /* before */ 'x' /* after */ } = options;
const { required: e3 /* left */ = 'x' } = options;
const {
  required: e4 =
    'a' +
    'b',
} = options;
takesCallback((value = (('p')), other /* n */ = 1 + 2) => {});
// Non-ASCII text on the same line.
const ñ = '😀'; const { required: 日本 = '語' } = options; const g1 = (ü: string | undefined = undefined) => ü;
