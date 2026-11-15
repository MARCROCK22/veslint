declare function dec(target: object, key: string | undefined, index: number): void;
function f1(a = 1, b: number) { return [a, b]; }
function f2(a?: number, b?: number, c = 1, d: number) { return [a, b, c, d]; }
function f3(this: object, a = 1, b: number) { return [this, a, b]; }
function f4(a: number, b = 1, ...c: number[]) { return [a, b, c]; }
function f5([a]: number[] = [], { b }: { b: number } = { b: 1 }, c: number) { return [a, b, c]; }
function f6([a]?: number[], c: number) { return [a, c]; }
const f7 = (a = 1, b: number) => [a, b];
const f8 = function (a: number = 1, b: number): number[] { return [a, b]; };
class C {
  constructor(public a = 1, private readonly b?: number, @dec protected c: number = 2, d: number) { void [d]; }
  m(a = 1, b: number) { return [a, b]; }
  get g() { return 1; }
  set s(v: number) { void v; }
}
const o = { m(a = 1, b: number) { return [a, b]; }, n: (a?: string, b = '') => [a, b] };
declare function f9(a?: number, b: number): void;
abstract class D { abstract m(a?: number, b: number): void; o(a?: number, b: number): void; o(a?: number, b?: number) { void [a, b]; } }
type T = (a?: number, b: number) => void;
function f10(a: number, b = 1, c?: number) { return [a, b, c]; }
function f11(a = 1, b = 2) { return [a, b]; }
function f12(
  a =
    1,
  b: number,
) { return [a, b]; }
export { f1, f2, f3, f4, f5, f6, f7, f8, C, o, f9, D, type T, f10, f11, f12 };
