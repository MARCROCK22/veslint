// no-unnecessary-type-arguments: the fix removes the last type argument, or the whole `<…>` if
// it is the only one. Non-ASCII text before the ranges: ñ 😀 日本語.
function one<T = number>(x?: T): void {}
function two<A, B = string>(a?: A, b?: B): void {}
function three<A, B = string, C = boolean>(a?: A, b?: B, c?: C): void {}
class Box<T = number> {
  constructor(public value?: T) {}
}
class Pair<A, B = string> {
  a?: A;
  b?: B;
}
interface IBox<T = number> {
  value?: T;
}
type Alias<A, B = string> = [A, B];
declare function tag<T = number>(strings: TemplateStringsArray): T;

// A single type argument: all of `<…>`.
one<number>();
new Box<number>();
const a1: IBox<number> = {};
class Sub extends Box<number> {}
class Impl implements IBox<number> {}
interface ISub extends IBox<number> {}
tag<number>`x`;
// The last of several: from the end of the previous one.
two<number, string>();
three<number, string, boolean>();
new Pair<number, string>();
const b1: Alias<number, string> = [1, 'x'];
// Spaces, comments and several lines.
one< number >();
one</* before */ number /* after */>();
two<number /* a */ , /* b */ string /* c */>();
two<
  number,
  string, // with a trailing comma
>();
new Pair<
  number, // the first
  string
>();
// Parentheses are not part of a type: the range starts inside those of the previous one.
one<(number)>();
two<(number), (string)>();
const c1: Alias<(number), string> = [1, 'x'];
const c2: Alias<number[], (string)> = [[1], 'x'];
// Non-ASCII text on the same line.
const ñ = '😀'; one<number>(); two<'日本', string>(); const d1: Alias<'語', string> = ['語', 'x'];
