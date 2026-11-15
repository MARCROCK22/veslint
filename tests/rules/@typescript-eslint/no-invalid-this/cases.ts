declare function dec(...args: unknown[]): (...a: any[]) => void;
console.log(this);
function f1() { return this; }
function f2(this: object) { return this; }
function f3(this: object) { return () => this; }
function f4(this: object) { function inner() { return this; } return inner; }
function f5(this: object, a = this) { return a; }
const f6 = function (this: object) { return this; };
const f7 = function () { return this; };
const f8 = () => this;
function* f9(this: object) { yield this; }
class C1 {
  a = this;
  b = () => this;
  c = function () { return this; };
  d = function (this: C1) { return this; };
  accessor e = this;
  declare g: number;
  @dec(this) h = 1;
  [`${this}`] = 2;
  static i = this;
  m() { return this; }
  n(this: C1) { return function () { return this; }; }
  static { console.log(this); }
  @dec(this) o() {}
}
abstract class C2 {
  abstract p: number;
  q = { r() { return this; }, s: function () { return this; } };
}
const o = {
  a() { return this; },
  b: function () { return this; },
  c: () => this,
  d(this: object) { return function () { return this; }; },
};
function Ctor() { this.x = 1; }
const v = function (this: object) { return [1].map(function () { return this; }); };
export { f1, f2, f3, f4, f5, f6, f7, f8, f9, C1, C2, o, Ctor, v };
